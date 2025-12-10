#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CSCardKeyValidator : NSObject

// 验证卡密
+ (void)validateCardKey:(NSString *)cardKey 
             completion:(void(^)(BOOL success, NSString *message, NSDate * _Nullable expireDate))completion;

// 检查是否已激活
+ (BOOL)isActivated;

// 获取到期时间
+ (NSDate * _Nullable)getExpireDate;

// 清除激活状态（用于测试）
+ (void)clearActivation;

@end

NS_ASSUME_NONNULL_END
