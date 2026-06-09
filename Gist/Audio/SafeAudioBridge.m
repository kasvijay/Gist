#import "SafeAudioBridge.h"

static NSError *GistErrorFromException(NSException *exception) {
    NSDictionary *info = @{
        NSLocalizedDescriptionKey: exception.reason ?: @"Unknown audio engine exception",
        @"GistExceptionName": exception.name ?: @"",
        @"GistExceptionUserInfo": exception.userInfo ?: @{},
    };
    return [NSError errorWithDomain:@"com.vijaykas.gist.SafeAudioBridge"
                               code:-1
                           userInfo:info];
}

BOOL GistInstallAudioTap(AVAudioInputNode *inputNode,
                        AVAudioFormat * _Nullable format,
                        AVAudioNodeBus bus,
                        AVAudioFrameCount bufferSize,
                        void (^block)(AVAudioPCMBuffer *buffer, AVAudioTime *when),
                        NSError * _Nullable * _Nullable error) {
    @try {
        [inputNode installTapOnBus:bus bufferSize:bufferSize format:format block:block];
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = GistErrorFromException(exception);
        }
        return NO;
    }
}

BOOL GistStartAudioEngine(AVAudioEngine *engine, NSError * _Nullable * _Nullable error) {
    @try {
        NSError *startError = nil;
        BOOL ok = [engine startAndReturnError:&startError];
        if (!ok && error) {
            *error = startError;
        }
        return ok;
    } @catch (NSException *exception) {
        if (error) {
            *error = GistErrorFromException(exception);
        }
        return NO;
    }
}
