#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Wraps `-[AVAudioInputNode installTapOnBus:bufferSize:format:block:]` in an
/// Objective-C @try/@catch so a format-mismatch (or any other) NSException
/// surfaces as an NSError instead of terminating the process.
///
/// Use `format = nil` to let the engine choose the bus's current format —
/// the only reliably crash-proof option across device changes.
///
/// Returns YES on success, NO on caught exception; `error` is filled when NO.
BOOL GistInstallAudioTap(AVAudioInputNode *inputNode,
                        AVAudioFormat * _Nullable format,
                        AVAudioNodeBus bus,
                        AVAudioFrameCount bufferSize,
                        void (^block)(AVAudioPCMBuffer *buffer, AVAudioTime *when),
                        NSError * _Nullable * _Nullable error);

/// Same NSException-safe wrapper for `-[AVAudioEngine startAndReturnError:]`.
/// `startAndReturnError:` already returns an NSError on most failures, but
/// the underlying CoreAudio layer can still raise NSExceptions on misconfigured
/// taps that survived install (rare but observed during Bluetooth profile
/// transitions). Catching them here lets the strategy loop fall through.
BOOL GistStartAudioEngine(AVAudioEngine *engine, NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
