#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface HBFaceRecognitionBridge : NSObject

- (nullable instancetype)initWithModelPath:(NSString *)modelPath error:(NSError * _Nullable *)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (nullable NSArray<NSDictionary<NSString *, id> *> *)recognizeImage:(CGImageRef)image
                                                                error:(NSError * _Nullable *)error;

@end

NS_ASSUME_NONNULL_END
