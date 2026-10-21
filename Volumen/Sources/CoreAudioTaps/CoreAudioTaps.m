#import "CoreAudioTaps.h"
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>

static AudioObjectPropertyAddress VOLAddress(AudioObjectPropertySelector selector) {
    return (AudioObjectPropertyAddress){selector, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
}

static NSError *VOLError(OSStatus status, NSString *what) {
    NSString *message = [NSString stringWithFormat:@"%@ (error %d).", what, (int)status];
    return [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *_Nullable VOLStringProperty(AudioObjectID object, AudioObjectPropertySelector selector) {
    AudioObjectPropertyAddress address = VOLAddress(selector);
    CFStringRef value = NULL;
    UInt32 size = sizeof(value);
    if (AudioObjectGetPropertyData(object, &address, 0, NULL, &size, &value) != noErr || value == NULL) return nil;
    return (__bridge_transfer NSString *)value;
}

static UInt32 VOLUInt32Property(AudioObjectID object, AudioObjectPropertySelector selector) {
    AudioObjectPropertyAddress address = VOLAddress(selector);
    UInt32 value = 0;
    UInt32 size = sizeof(value);
    AudioObjectGetPropertyData(object, &address, 0, NULL, &size, &value);
    return value;
}

#pragma mark - Procesos

@interface VOLProcess ()
- (instancetype)initWithObjectID:(AudioObjectID)objectID;
@end

@implementation VOLProcess

- (instancetype)initWithObjectID:(AudioObjectID)objectID {
    if ((self = [super init])) {
        _objectID = objectID;
        AudioObjectPropertyAddress address = VOLAddress(kAudioProcessPropertyPID);
        pid_t pid = -1;
        UInt32 size = sizeof(pid);
        AudioObjectGetPropertyData(objectID, &address, 0, NULL, &size, &pid);
        _pid = pid;
        _bundleID = VOLStringProperty(objectID, kAudioProcessPropertyBundleID) ?: @"";
        _isRunningOutput = VOLUInt32Property(objectID, kAudioProcessPropertyIsRunningOutput) != 0;
    }
    return self;
}

@end

@implementation VOLSystem

+ (NSArray<VOLProcess *> *)processes {
    AudioObjectPropertyAddress address = VOLAddress(kAudioHardwarePropertyProcessObjectList);
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &size) != noErr || size == 0) return @[];
    AudioObjectID *ids = malloc(size);
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, ids) != noErr) {
        free(ids);
        return @[];
    }
    NSMutableArray<VOLProcess *> *processes = [NSMutableArray array];
    for (UInt32 i = 0; i < size / sizeof(AudioObjectID); i++) {
        [processes addObject:[[VOLProcess alloc] initWithObjectID:ids[i]]];
    }
    free(ids);
    return processes;
}

+ (nullable NSString *)defaultOutputDeviceUID {
    AudioObjectPropertyAddress address = VOLAddress(kAudioHardwarePropertyDefaultOutputDevice);
    AudioDeviceID device = kAudioObjectUnknown;
    UInt32 size = sizeof(device);
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &device) != noErr
        || device == kAudioObjectUnknown) return nil;
    return VOLStringProperty(device, kAudioDevicePropertyDeviceUID);
}

+ (void)observeChanges:(void (^)(void))handler {
    AudioObjectPropertyListenerBlock listener = ^(UInt32 count, const AudioObjectPropertyAddress *addresses) {
        handler();
    };
    AudioObjectPropertySelector selectors[] = {kAudioHardwarePropertyProcessObjectList,
                                               kAudioHardwarePropertyDefaultOutputDevice};
    for (size_t i = 0; i < sizeof(selectors) / sizeof(selectors[0]); i++) {
        AudioObjectPropertyAddress address = VOLAddress(selectors[i]);
        AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject, &address, dispatch_get_main_queue(), listener);
    }
}

@end

#pragma mark - Procesado del sonido (en tiempo real: sin memoria nueva, bloqueos ni Objective-C)

static UInt32 VOLChannelCount(const AudioBufferList *list) {
    UInt32 count = 0;
    for (UInt32 b = 0; b < list->mNumberBuffers; b++) count += list->mBuffers[b].mNumberChannels;
    return count;
}

/// Primera muestra del canal `channel` (contando todos los búferes), con la distancia entre muestras
/// y el número de muestras. Sirve tanto para audio entrelazado como separado por canales.
static float *VOLChannel(const AudioBufferList *list, UInt32 channel, UInt32 *stride, UInt32 *frames) {
    for (UInt32 b = 0; b < list->mNumberBuffers; b++) {
        const AudioBuffer *buffer = &list->mBuffers[b];
        UInt32 channels = buffer->mNumberChannels;
        if (channel < channels) {
            if (buffer->mData == NULL) return NULL;
            *stride = channels;
            *frames = buffer->mDataByteSize / (UInt32)(sizeof(float) * channels);
            return (float *)buffer->mData + channel;
        }
        channel -= channels;
    }
    return NULL;
}

static void VOLCopyScaled(const AudioBufferList *input, AudioBufferList *output, float gain) {
    for (UInt32 b = 0; b < output->mNumberBuffers; b++) {
        if (output->mBuffers[b].mData) memset(output->mBuffers[b].mData, 0, output->mBuffers[b].mDataByteSize);
    }
    if (input == NULL) return;
    UInt32 inputChannels = VOLChannelCount(input);
    if (inputChannels == 0) return;
    // El tap (estéreo) va al final de las entradas del dispositivo agregado: antes pueden estar
    // las entradas de la propia salida, como el micrófono de unos auriculares USB.
    UInt32 tapChannels = MIN(inputChannels, 2);
    UInt32 firstTapChannel = inputChannels - tapChannels;
    // Solo los dos primeros canales de la salida: izquierdo y derecho.
    UInt32 outputChannels = MIN(VOLChannelCount(output), 2);
    for (UInt32 c = 0; c < outputChannels; c++) {
        UInt32 inStride = 0, inFrames = 0, outStride = 0, outFrames = 0;
        const float *source = VOLChannel(input, firstTapChannel + c % tapChannels, &inStride, &inFrames);
        float *destination = VOLChannel(output, c, &outStride, &outFrames);
        if (source == NULL || destination == NULL) continue;
        UInt32 frames = MIN(inFrames, outFrames);
        for (UInt32 f = 0; f < frames; f++) {
            float sample = source[f * inStride] * gain;
            destination[f * outStride] = sample > 1 ? 1 : (sample < -1 ? -1 : sample);
        }
    }
}

#pragma mark - Tap por app

@implementation VOLAppTap {
    AudioObjectID _tap;
    AudioObjectID _aggregate;
    AudioDeviceIOProcID _ioProc;
    /// Memoria propia para el volumen: el bloque de audio la lee sin tocar el objeto.
    float *_gain;
}

- (nullable instancetype)initWithProcesses:(NSArray<NSNumber *> *)objectIDs
                           outputDeviceUID:(NSString *)outputDeviceUID
                                     error:(NSError **)error {
    if (!(self = [super init])) return nil;
    _processes = [objectIDs copy];
    _outputDeviceUID = [outputDeviceUID copy];
    _tap = kAudioObjectUnknown;
    _aggregate = kAudioObjectUnknown;
    _gain = malloc(sizeof(float));
    *_gain = 1;

    // 1. Tap que capta el sonido de los procesos y lo silencia en la salida normal.
    CATapDescription *description = [[CATapDescription alloc] initStereoMixdownOfProcesses:objectIDs];
    description.muteBehavior = CATapMutedWhenTapped;
    if ([description respondsToSelector:NSSelectorFromString(@"setUUID:")]) {
        [description setValue:[NSUUID UUID] forKey:@"UUID"];
    }
    OSStatus status = AudioHardwareCreateProcessTap(description, &_tap);
    if (status != noErr) {
        if (error) *error = VOLError(status, @"No se pudo captar el sonido de la app");
        [self invalidate];
        return nil;
    }
    NSString *tapUID = VOLStringProperty(_tap, kAudioTapPropertyUID);
    if (tapUID == nil) {
        if (error) *error = VOLError(kAudioHardwareUnspecifiedError, @"El tap no tiene identificador");
        [self invalidate];
        return nil;
    }

    // 2. Dispositivo agregado privado: la salida de sonido actual más el tap como entrada.
    NSDictionary *aggregate = @{
        @kAudioAggregateDeviceNameKey: @"Volumen",
        @kAudioAggregateDeviceUIDKey: [NSUUID UUID].UUIDString,
        @kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
        @kAudioAggregateDeviceIsPrivateKey: @YES,
        @kAudioAggregateDeviceIsStackedKey: @NO,
        @kAudioAggregateDeviceTapAutoStartKey: @YES,
        @kAudioAggregateDeviceSubDeviceListKey: @[@{@kAudioSubDeviceUIDKey: outputDeviceUID}],
        @kAudioAggregateDeviceTapListKey: @[@{@kAudioSubTapDriftCompensationKey: @YES, @kAudioSubTapUIDKey: tapUID}],
    };
    status = AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)aggregate, &_aggregate);
    if (status != noErr) {
        if (error) *error = VOLError(status, @"No se pudo preparar la salida de sonido");
        [self invalidate];
        return nil;
    }

    // 3. El sonido captado se envía a la salida con el volumen elegido.
    float *gain = _gain;
    status = AudioDeviceCreateIOProcIDWithBlock(&_ioProc, _aggregate, NULL,
        ^(const AudioTimeStamp *now, const AudioBufferList *input, const AudioTimeStamp *inputTime,
          AudioBufferList *output, const AudioTimeStamp *outputTime) {
            VOLCopyScaled(input, output, *gain);
        });
    if (status == noErr) status = AudioDeviceStart(_aggregate, _ioProc);
    if (status != noErr) {
        if (error) *error = VOLError(status, @"No se pudo reproducir el sonido");
        [self invalidate];
        return nil;
    }
    return self;
}

- (float)volume { return *_gain; }
- (void)setVolume:(float)volume { *_gain = volume; }

- (void)invalidate {
    if (_aggregate != kAudioObjectUnknown) {
        if (_ioProc != NULL) {
            AudioDeviceStop(_aggregate, _ioProc);
            AudioDeviceDestroyIOProcID(_aggregate, _ioProc);
            _ioProc = NULL;
        }
        AudioHardwareDestroyAggregateDevice(_aggregate);
        _aggregate = kAudioObjectUnknown;
    }
    if (_tap != kAudioObjectUnknown) {
        AudioHardwareDestroyProcessTap(_tap);
        _tap = kAudioObjectUnknown;
    }
}

- (void)dealloc {
    [self invalidate];
    free(_gain);
}

@end
