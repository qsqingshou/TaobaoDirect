#import "CSCardKeyValidator.h"
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonCryptor.h>
#import <UIKit/UIKit.h>

// 云验证配置
static NSString * const kWeiURL = @"http://wy.llua.cn";
static NSString * const kWeiAID = @"11644";
static NSString * const kWeiKEY = @"73758u537577i3t7";
static NSString * const kRC4KEY = @"ElFlF870vDk88gef";
static NSInteger const kDLCODE = 200;

// 本地存储Key
static NSString * const kActivatedKey = @"com.wechat.tweak.cardkey.activated";
static NSString * const kExpireDateKey = @"com.wechat.tweak.cardkey.expiredate";

@implementation CSCardKeyValidator

#pragma mark - Public Methods

+ (void)validateCardKey:(NSString *)cardKey completion:(void(^)(BOOL success, NSString *message, NSDate * _Nullable expireDate))completion {
    if (!cardKey || cardKey.length == 0) {
        if (completion) {
            completion(NO, @"请输入卡密", nil);
        }
        return;
    }
    
    // 获取设备唯一标识
    NSString *deviceID = [self getDeviceID];
    
    // 获取时间戳
    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
    NSInteger TIME = (NSInteger)timestamp;
    
    // 生成VALUE（用于二次校验）
    NSInteger VALUE = 1 + arc4random_uniform(10) + TIME;
    
    // 生成签名
    NSString *signString = [NSString stringWithFormat:@"kami=%@&markcode=%@&t=%ld&%@", 
                           cardKey, deviceID, (long)TIME, kWeiKEY];
    NSString *SIGN = [self md5:signString];
    
    // 组装请求参数并加密
    NSString *dataString = [NSString stringWithFormat:@"kami=%@&markcode=%@&t=%ld&sign=%@&value=%ld",
                           cardKey, deviceID, (long)TIME, SIGN, (long)VALUE];
    NSString *encryptedData = [self rc4Encrypt:dataString key:kRC4KEY];
    
    NSLog(@"[卡密验证] 请求参数: kami=%@, markcode=%@, time=%ld, sign=%@, value=%ld", cardKey, deviceID, (long)TIME, SIGN, (long)VALUE);
    
    // 发起网络请求
    NSString *urlString = [NSString stringWithFormat:@"%@/api/?id=kmlogon&app=%@&data=%@", 
                          kWeiURL, kWeiAID, encryptedData];
    NSURL *url = [NSURL URLWithString:[urlString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error || !data) {
            NSLog(@"[卡密验证] 网络请求失败: %@", error);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(NO, @"网络请求失败，请检查网络连接", nil);
                }
            });
            return;
        }
        
        // 解密响应数据
        NSString *responseHex = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSLog(@"[卡密验证] 收到响应: %@", responseHex);
        
        NSString *decryptedResponse = [self rc4Decrypt:responseHex key:kRC4KEY];
        NSLog(@"[卡密验证] 解密后: %@", decryptedResponse);
        
        if (!decryptedResponse) {
            NSLog(@"[卡密验证] RC4解密失败");
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(NO, @"数据解密失败", nil);
                }
            });
            return;
        }
        
        // 解析JSON
        NSError *jsonError = nil;
        NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:[decryptedResponse dataUsingEncoding:NSUTF8StringEncoding] 
                                                                    options:0 
                                                                      error:&jsonError];
        
        if (jsonError || !responseDict) {
            NSLog(@"[卡密验证] JSON解析失败: %@, 原始数据: %@", jsonError, decryptedResponse);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    NSString *errorMsg = jsonError ? jsonError.localizedDescription : @"数据格式错误";
                    completion(NO, errorMsg, nil);
                }
            });
            return;
        }
        
        NSLog(@"[卡密验证] JSON解析成功: %@", responseDict);
        
        // 检查响应码
        NSInteger code = [responseDict[@"code"] integerValue];
        NSLog(@"[卡密验证] 响应码: %ld", (long)code);
        
        if (code == kDLCODE) {
            // 验证check值
            NSString *check = responseDict[@"check"];
            NSString *check2 = responseDict[@"check2"];
            id timeObj = responseDict[@"time"];
            NSString *timeStr = [NSString stringWithFormat:@"%@", timeObj];
            
            NSString *expectedCheck = [self md5:[NSString stringWithFormat:@"%@%@%ld", timeStr, kWeiKEY, (long)VALUE]];
            NSLog(@"[卡密验证] check=%@, expectedCheck=%@, check2=%@", check, expectedCheck, check2);
            
            if ([check isEqualToString:expectedCheck]) {
                // 验证成功，获取到期时间
                NSDictionary *msg = responseDict[@"msg"];
                NSTimeInterval vipTimestamp = [msg[@"vip"] doubleValue];
                NSDate *expireDate = [NSDate dateWithTimeIntervalSince1970:vipTimestamp];
                
                NSLog(@"[卡密验证] 验证成功! 到期时间: %@", expireDate);
                
                // 保存激活状态
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kActivatedKey];
                [[NSUserDefaults standardUserDefaults] setObject:expireDate forKey:kExpireDateKey];
                [[NSUserDefaults standardUserDefaults] synchronize];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) {
                        completion(YES, @"激活成功", expireDate);
                    }
                });
            } else {
                NSLog(@"[卡密验证] check校验失败");
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) {
                        completion(NO, @"数据校验失败", nil);
                    }
                });
            }
        } else {
            // 获取错误信息
            id msgObj = responseDict[@"msg"];
            NSString *errorMsg;
            
            if ([msgObj isKindOfClass:[NSString class]]) {
                errorMsg = (NSString *)msgObj;
            } else if ([msgObj isKindOfClass:[NSDictionary class]]) {
                errorMsg = @"卡密验证失败";
            } else {
                errorMsg = [NSString stringWithFormat:@"验证失败(code:%ld)", (long)code];
            }
            
            NSLog(@"[卡密验证] 验证失败: %@", errorMsg);
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(NO, errorMsg, nil);
                }
            });
        }
    }];
    
    [task resume];
}

+ (BOOL)isActivated {
    BOOL activated = [[NSUserDefaults standardUserDefaults] boolForKey:kActivatedKey];
    if (!activated) {
        return NO;
    }
    
    // 检查是否过期
    NSDate *expireDate = [self getExpireDate];
    if (!expireDate) {
        return NO;
    }
    
    NSDate *now = [NSDate date];
    return [now compare:expireDate] == NSOrderedAscending;
}

+ (NSDate *)getExpireDate {
    return [[NSUserDefaults standardUserDefaults] objectForKey:kExpireDateKey];
}

+ (void)clearActivation {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kActivatedKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kExpireDateKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Private Methods

// MD5加密
+ (NSString *)md5:(NSString *)input {
    const char *cStr = [input UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cStr, (CC_LONG)strlen(cStr), digest);
    
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", digest[i]];
    }
    
    return output;
}

// RC4加密
+ (NSString *)rc4Encrypt:(NSString *)input key:(NSString *)key {
    NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
    NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
    
    NSData *encrypted = [self rc4Process:data key:keyData];
    
    // 转换为十六进制字符串
    NSMutableString *hex = [NSMutableString string];
    const unsigned char *bytes = encrypted.bytes;
    for (NSInteger i = 0; i < encrypted.length; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    
    return hex;
}

// RC4解密
+ (NSString *)rc4Decrypt:(NSString *)hex key:(NSString *)key {
    // 将十六进制字符串转换为NSData
    NSMutableData *data = [NSMutableData data];
    for (NSInteger i = 0; i < hex.length; i += 2) {
        NSString *byteString = [hex substringWithRange:NSMakeRange(i, 2)];
        unsigned char byte = (unsigned char)strtol([byteString UTF8String], NULL, 16);
        [data appendBytes:&byte length:1];
    }
    
    NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
    NSData *decrypted = [self rc4Process:data key:keyData];
    
    return [[NSString alloc] initWithData:decrypted encoding:NSUTF8StringEncoding];
}

// RC4处理（加密和解密使用同一算法）
+ (NSData *)rc4Process:(NSData *)data key:(NSData *)key {
    unsigned char S[256];
    for (int i = 0; i < 256; i++) {
        S[i] = i;
    }
    
    const unsigned char *keyBytes = key.bytes;
    NSInteger keyLength = key.length;
    
    int j = 0;
    for (int i = 0; i < 256; i++) {
        j = (j + S[i] + keyBytes[i % keyLength]) % 256;
        unsigned char temp = S[i];
        S[i] = S[j];
        S[j] = temp;
    }
    
    const unsigned char *inputBytes = data.bytes;
    NSInteger length = data.length;
    NSMutableData *result = [NSMutableData dataWithLength:length];
    unsigned char *resultBytes = result.mutableBytes;
    
    int i = 0;
    j = 0;
    for (NSInteger k = 0; k < length; k++) {
        i = (i + 1) % 256;
        j = (j + S[i]) % 256;
        
        unsigned char temp = S[i];
        S[i] = S[j];
        S[j] = temp;
        
        unsigned char K = S[(S[i] + S[j]) % 256];
        resultBytes[k] = inputBytes[k] ^ K;
    }
    
    return result;
}

// 获取设备唯一标识
+ (NSString *)getDeviceID {
    // 使用IDFV作为设备标识
    NSString *idfv = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    if (idfv) {
        return idfv;
    }
    
    // 如果无法获取IDFV，使用设备名称+系统版本作为标识
    NSString *deviceName = [[UIDevice currentDevice] name];
    NSString *systemVersion = [[UIDevice currentDevice] systemVersion];
    return [self md5:[NSString stringWithFormat:@"%@_%@", deviceName, systemVersion]];
}

@end
