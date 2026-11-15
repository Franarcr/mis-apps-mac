#import "OidoAudio.h"
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>

static AudioObjectPropertyAddress OIDAddress(AudioObjectPropertySelector selector) {
    return (AudioObjectPropertyAddress){selector, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
}

static NSError *OIDError(OSStatus status, NSString *what) {
    NSString *message = [NSString stringWithFormat:@"%@ (error %d).", what, (int)status];
    return [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *_Nullable OIDStringProperty(AudioObjectID object, AudioObjectPropertySelector selector) {
    AudioObjectPropertyAddress address = OIDAddress(selector);
    CFStringRef value = NULL;
    UInt32 size = sizeof(value);
    if (AudioObjectGetPropertyData(object, &address, 0, NULL, &size, &value) != noErr || value == NULL) return nil;
    return (__bridge_transfer NSString *)value;
}

static UInt32 OIDUInt32Property(AudioObjectID object, AudioObjectPropertySelector selector) {
    AudioObjectPropertyAddress address = OIDAddress(selector);
    UInt32 value = 0;
    UInt32 size = sizeof(value);
    AudioObjectGetPropertyData(object, &address, 0, NULL, &size, &value);
    return value;
}

#pragma mark - Procesos

@interface OIDProcess ()
- (instancetype)initWithObjectID:(AudioObjectID)objectID;
@end

@implementation OIDProcess

- (instancetype)initWithObjectID:(AudioObjectID)objectID {
    if ((self = [super init])) {
        _objectID = objectID;
        AudioObjectPropertyAddress address = OIDAddress(kAudioProcessPropertyPID);
        pid_t pid = -1;
        UInt32 size = sizeof(pid);
        AudioObjectGetPropertyData(objectID, &address, 0, NULL, &size, &pid);
        _pid = pid;
        _bundleID = OIDStringProperty(objectID, kAudioProcessPropertyBundleID) ?: @"";
        _isRunningInput = OIDUInt32Property(objectID, kAudioProcessPropertyIsRunningInput) != 0;
        _isRunningOutput = OIDUInt32Property(objectID, kAudioProcessPropertyIsRunningOutput) != 0;
    }
    return self;
}

@end

@implementation OIDSystem

+ (NSArray<OIDProcess *> *)processes {
    AudioObjectPropertyAddress address = OIDAddress(kAudioHardwarePropertyProcessObjectList);
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &size) != noErr || size == 0) return @[];
    AudioObjectID *ids = malloc(size);
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, ids) != noErr) {
        free(ids);
        return @[];
    }
    NSMutableArray<OIDProcess *> *processes = [NSMutableArray array];
    for (UInt32 i = 0; i < size / sizeof(AudioObjectID); i++) {
        [processes addObject:[[OIDProcess alloc] initWithObjectID:ids[i]]];
    }
    free(ids);
    return processes;
}

@end

#pragma mark - Grabación (el bloque de audio corre en tiempo real: sin memoria nueva ni bloqueos)

/// Muestras que caben en la memoria preparada para cada bloque de audio.
static const UInt32 OIDMaxFrames = 16384;

@implementation OIDTapRecorder {
    AudioObjectID _tap;
    AudioObjectID _aggregate;
    AudioDeviceIOProcID _ioProc;
    ExtAudioFileRef _file;
    float *_samples;
    float *_level;
}

- (nullable instancetype)initWithProcesses:(NSArray<NSNumber *> *)objectIDs
                                    fileURL:(NSURL *)fileURL
                                      error:(NSError **)error {
    if (!(self = [super init])) return nil;
    _tap = kAudioObjectUnknown;
    _aggregate = kAudioObjectUnknown;
    _samples = calloc(OIDMaxFrames, sizeof(float));
    _level = calloc(1, sizeof(float));

    // 1. Tap en mono que copia el sonido sin silenciarlo.
    CATapDescription *description = objectIDs.count > 0
        ? [[CATapDescription alloc] initMonoMixdownOfProcesses:objectIDs]
        : [[CATapDescription alloc] initMonoGlobalTapButExcludeProcesses:@[]];
    description.muteBehavior = CATapUnmuted;
    description.name = @"Oído";
    description.privateTap = YES;
    if ([description respondsToSelector:NSSelectorFromString(@"setUUID:")]) {
        [description setValue:[NSUUID UUID] forKey:@"UUID"];
    }
    OSStatus status = AudioHardwareCreateProcessTap(description, &_tap);
    if (status != noErr) {
        if (error) *error = OIDError(status, @"No se pudo captar el sonido de la llamada");
        [self stop];
        return nil;
    }
    NSString *tapUID = OIDStringProperty(_tap, kAudioTapPropertyUID);

    // 2. Dispositivo agregado privado con la salida actual (da el reloj) y el tap como entrada.
    AudioObjectPropertyAddress outputAddress = OIDAddress(kAudioHardwarePropertyDefaultOutputDevice);
    AudioDeviceID output = kAudioObjectUnknown;
    UInt32 size = sizeof(output);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &outputAddress, 0, NULL, &size, &output);
    NSString *outputUID = output != kAudioObjectUnknown ? OIDStringProperty(output, kAudioDevicePropertyDeviceUID) : nil;
    if (tapUID == nil || outputUID == nil) {
        if (error) *error = OIDError(kAudioHardwareUnspecifiedError, @"No hay salida de sonido");
        [self stop];
        return nil;
    }
    NSDictionary *aggregate = @{
        @kAudioAggregateDeviceNameKey: @"Oído",
        @kAudioAggregateDeviceUIDKey: [NSUUID UUID].UUIDString,
        @kAudioAggregateDeviceMainSubDeviceKey: outputUID,
        @kAudioAggregateDeviceIsPrivateKey: @YES,
        @kAudioAggregateDeviceIsStackedKey: @NO,
        @kAudioAggregateDeviceTapAutoStartKey: @YES,
        @kAudioAggregateDeviceSubDeviceListKey: @[@{@kAudioSubDeviceUIDKey: outputUID}],
        @kAudioAggregateDeviceTapListKey: @[@{@kAudioSubTapDriftCompensationKey: @YES, @kAudioSubTapUIDKey: tapUID}],
    };
    status = AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)aggregate, &_aggregate);
    if (status != noErr) {
        if (error) *error = OIDError(status, @"No se pudo preparar la grabación");
        [self stop];
        return nil;
    }
    Float64 sampleRate = 48000;
    AudioObjectPropertyAddress rateAddress = OIDAddress(kAudioDevicePropertyNominalSampleRate);
    size = sizeof(sampleRate);
    AudioObjectGetPropertyData(_aggregate, &rateAddress, 0, NULL, &size, &sampleRate);
    if (sampleRate < 8000) sampleRate = 48000;

    // 3. Archivo AAC; se le entregan muestras float en mono.
    AudioStreamBasicDescription fileFormat = {0};
    fileFormat.mFormatID = kAudioFormatMPEG4AAC;
    fileFormat.mSampleRate = sampleRate;
    fileFormat.mChannelsPerFrame = 1;
    status = ExtAudioFileCreateWithURL((__bridge CFURLRef)fileURL, kAudioFileM4AType, &fileFormat, NULL,
                                       kAudioFileFlags_EraseFile, &_file);
    if (status != noErr) {
        if (error) *error = OIDError(status, @"No se pudo crear el archivo de audio");
        [self stop];
        return nil;
    }
    AudioStreamBasicDescription client = {0};
    client.mFormatID = kAudioFormatLinearPCM;
    client.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    client.mSampleRate = sampleRate;
    client.mChannelsPerFrame = 1;
    client.mBitsPerChannel = 32;
    client.mBytesPerFrame = 4;
    client.mFramesPerPacket = 1;
    client.mBytesPerPacket = 4;
    ExtAudioFileSetProperty(_file, kExtAudioFileProperty_ClientDataFormat, sizeof(client), &client);
    // La primera llamada prepara la escritura en segundo plano fuera del hilo de audio.
    ExtAudioFileWriteAsync(_file, 0, NULL);

    // 4. Cada bloque: el último canal de entrada es el tap.
    ExtAudioFileRef file = _file;
    float *samples = _samples;
    float *level = _level;
    status = AudioDeviceCreateIOProcIDWithBlock(&_ioProc, _aggregate, NULL,
        ^(const AudioTimeStamp *now, const AudioBufferList *input, const AudioTimeStamp *inputTime,
          AudioBufferList *outputList, const AudioTimeStamp *outputTime) {
            if (input == NULL || input->mNumberBuffers == 0) return;
            const AudioBuffer *buffer = &input->mBuffers[input->mNumberBuffers - 1];
            UInt32 channels = buffer->mNumberChannels;
            if (buffer->mData == NULL || channels == 0) return;
            UInt32 frames = buffer->mDataByteSize / (UInt32)(sizeof(float) * channels);
            if (frames > OIDMaxFrames) frames = OIDMaxFrames;
            const float *source = (const float *)buffer->mData + (channels - 1);
            float peak = 0;
            for (UInt32 f = 0; f < frames; f++) {
                float s = source[f * channels];
                samples[f] = s;
                float a = s < 0 ? -s : s;
                if (a > peak) peak = a;
            }
            *level = peak > *level ? peak : *level * 0.9f;
            AudioBufferList list;
            list.mNumberBuffers = 1;
            list.mBuffers[0].mNumberChannels = 1;
            list.mBuffers[0].mDataByteSize = frames * sizeof(float);
            list.mBuffers[0].mData = samples;
            ExtAudioFileWriteAsync(file, frames, &list);
        });
    if (status == noErr) status = AudioDeviceStart(_aggregate, _ioProc);
    if (status != noErr) {
        if (error) *error = OIDError(status, @"No se pudo empezar a grabar");
        [self stop];
        return nil;
    }
    return self;
}

- (float)level { return _level ? *_level : 0; }

- (void)stop {
    if (_aggregate != kAudioObjectUnknown) {
        if (_ioProc != NULL) {
            AudioDeviceStop(_aggregate, _ioProc);
            AudioDeviceDestroyIOProcID(_aggregate, _ioProc);
            _ioProc = NULL;
        }
        AudioHardwareDestroyAggregateDevice(_aggregate);
        _aggregate = kAudioObjectUnknown;
    }
    if (_file != NULL) {
        ExtAudioFileDispose(_file);
        _file = NULL;
    }
    if (_tap != kAudioObjectUnknown) {
        AudioHardwareDestroyProcessTap(_tap);
        _tap = kAudioObjectUnknown;
    }
}

- (void)dealloc {
    [self stop];
    free(_samples);
    free(_level);
}

@end
