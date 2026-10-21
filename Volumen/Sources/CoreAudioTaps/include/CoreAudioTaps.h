#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

NS_ASSUME_NONNULL_BEGIN

/// Un proceso que usa el audio: una app o uno de sus procesos auxiliares
/// (Safari y Chrome, por ejemplo, reproducen desde procesos aparte).
@interface VOLProcess : NSObject
@property (nonatomic, readonly) AudioObjectID objectID;
@property (nonatomic, readonly) pid_t pid;
/// Identificador del paquete; vacío si el proceso no tiene.
@property (nonatomic, readonly, copy) NSString *bundleID;
/// Está sonando ahora mismo.
@property (nonatomic, readonly) BOOL isRunningOutput;
@end

@interface VOLSystem : NSObject
/// Todos los procesos que han usado el audio.
+ (NSArray<VOLProcess *> *)processes;
/// Identificador de la salida de sonido elegida (altavoces, auriculares…).
+ (nullable NSString *)defaultOutputDeviceUID;
/// Avisa en el hilo principal cuando cambian los procesos con audio o la salida de sonido.
+ (void)observeChanges:(void (^)(void))handler;
@end

/// Cambia el volumen de un grupo de procesos: el tap los silencia y el sonido capturado
/// se vuelve a enviar a la salida con el volumen elegido.
@interface VOLAppTap : NSObject
- (nullable instancetype)initWithProcesses:(NSArray<NSNumber *> *)objectIDs
                           outputDeviceUID:(NSString *)outputDeviceUID
                                     error:(NSError **)error;
- (instancetype)init NS_UNAVAILABLE;
@property (nonatomic, readonly, copy) NSArray<NSNumber *> *processes;
@property (nonatomic, readonly, copy) NSString *outputDeviceUID;
/// 0 = silencio, 1 = sin cambios, hasta 1,5 = más fuerte.
@property (nonatomic) float volume;
/// Detiene el tap; el sonido de la app vuelve a su volumen normal.
- (void)invalidate;
@end

NS_ASSUME_NONNULL_END
