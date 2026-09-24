#import "FaceRecognitionBridge.h"
#import "Native/include/facedetect_capi.h"

#include <climits>
#include <cstdint>
#include <vector>

static NSError *FaceRecognitionError(NSString *message) {
    return [NSError errorWithDomain:@"HomeBuddy.FaceRecognition" code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@interface HBFaceRecognitionBridge () {
    facedetect_ctx *_context;
}
@end

@implementation HBFaceRecognitionBridge

- (nullable instancetype)initWithModelPath:(NSString *)modelPath error:(NSError **)error {
    self = [super init];
    if (!self) return nil;

    _context = [modelPath fileSystemRepresentation]
        ? facedetect_capi_load([modelPath fileSystemRepresentation])
        : nullptr;
    if (!_context) {
        if (error) *error = FaceRecognitionError(@"无法加载人脸识别 GGUF 模型，请检查文件路径和模型格式。");
        return nil;
    }
    return self;
}

- (void)dealloc {
    facedetect_capi_free(_context);
}

- (nullable NSArray<NSDictionary<NSString *, id> *> *)recognizeImage:(CGImageRef)image
                                                                error:(NSError **)error {
    if (!_context || !image) {
        if (error) *error = FaceRecognitionError(@"人脸识别模型尚未加载或照片为空。");
        return nil;
    }

    const size_t width = CGImageGetWidth(image);
    const size_t height = CGImageGetHeight(image);
    if (width == 0 || height == 0 || width > INT_MAX || height > INT_MAX ||
        width > SIZE_MAX / height / 4) {
        if (error) *error = FaceRecognitionError(@"照片尺寸无效。");
        return nil;
    }

    const size_t bytesPerRow = width * 4;
    std::vector<unsigned char> rgba(bytesPerRow * height);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (!colorSpace) {
        if (error) *error = FaceRecognitionError(@"无法创建照片颜色空间。");
        return nil;
    }
    CGContextRef bitmap = CGBitmapContextCreate(
        rgba.data(), width, height, 8, bytesPerRow, colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!bitmap) {
        if (error) *error = FaceRecognitionError(@"无法读取照片像素。");
        return nil;
    }
    CGContextDrawImage(bitmap, CGRectMake(0, 0, width, height), image);
    CGContextRelease(bitmap);

    std::vector<unsigned char> rgb(width * height * 3);
    for (size_t pixel = 0, count = width * height; pixel < count; ++pixel) {
        rgb[pixel * 3] = rgba[pixel * 4];
        rgb[pixel * 3 + 1] = rgba[pixel * 4 + 1];
        rgb[pixel * 3 + 2] = rgba[pixel * 4 + 2];
    }

    facedetect_embedding_result *result = facedetect_capi_recognize_rgb(
        _context, rgb.data(), (int)width, (int)height);
    if (!result) {
        const char *lastError = facedetect_capi_last_error(_context);
        NSString *message = lastError ? [NSString stringWithUTF8String:lastError] : nil;
        if (error) *error = FaceRecognitionError(message.length ? message : @"人脸检测或 embedding 推理失败。");
        return nil;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *faces =
        [NSMutableArray arrayWithCapacity:(NSUInteger)result->face_count];
    for (int index = 0; index < result->face_count; ++index) {
        const facedetect_face_embedding *face = &result->faces[index];
        NSMutableArray<NSNumber *> *embedding =
            [NSMutableArray arrayWithCapacity:(NSUInteger)result->embedding_dim];
        const float *values = result->embeddings + (size_t)index * result->embedding_dim;
        for (int component = 0; component < result->embedding_dim; ++component) {
            [embedding addObject:@(values[component])];
        }
        [faces addObject:@{
            @"score": @(face->score),
            @"x1": @(face->box[0]), @"y1": @(face->box[1]),
            @"x2": @(face->box[2]), @"y2": @(face->box[3]),
            @"embedding": embedding
        }];
    }
    facedetect_capi_free_embedding_result(result);
    return faces;
}

@end
