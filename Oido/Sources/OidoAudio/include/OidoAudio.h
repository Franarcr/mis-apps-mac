#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

NS_ASSUME_NONNULL_BEGIN

/// Un proceso que ha usado el audio: una app o uno de sus procesos auxiliares.
@interface OIDProcess : NSObject
@property (nonatomic, readonly) AudioObjectID objectID;
@property (nonatomic, readonly) pid_t pid;
/// Identificador del paquete; vacío si el proceso no tiene.
@property (nonatomic, readonly, copy) NSString *bundleID;
/// Está usando el micrófono ahora mismo.
@property (nonatomic, readonly) BOOL isRunningInput;
/// Está sonando ahora mismo.
@property (nonatomic, readonly) BOOL isRunningOutput;
@end

@interface OIDSystem : NSObject
+ (NSArray<OIDProcess *> *)processes;
@end

/// Graba en un archivo M4A (mono) lo que suenan unos procesos, o todo el Mac si la lista está vacía.
/// El sonido sigue oyéndose normal: solo se copia.
@interface OIDTapRecorder : NSObject
- (nullable instancetype)initWithProcesses:(NSArray<NSNumber *> *)objectIDs
                                    fileURL:(NSURL *)fileURL
                                      error:(NSError **)error;
- (instancetype)init NS_UNAVAILABLE;
/// Nivel del sonido reciente (0 a 1), para mostrar que llega audio.
@property (nonatomic, readonly) float level;
/// Termina la grabación y cierra el archivo.
- (void)stop;
@end

NS_ASSUME_NONNULL_END
