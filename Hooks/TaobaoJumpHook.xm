// 淘口令自动跳转淘宝功能
// 思路：Hook 微信自定义菜单，添加"跳转淘宝"按钮
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../Headers/WCHeaders.h"

// 检查淘口令跳转功能是否启用
static BOOL isTaobaoJumpEnabled() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL enabled = [defaults boolForKey:@"TaobaoJump_Enabled"];
    return enabled;
}

// 存储当前长按的消息内容
static NSString *currentMessageContent = nil;

// 跳转到淘宝
static void jumpToTaobao() {
    if (!currentMessageContent || currentMessageContent.length == 0) {
        NSLog(@"[TaobaoJump] ❌ 没有消息内容");
        return;
    }
    
    NSLog(@"[TaobaoJump] 准备跳转淘宝，内容: %@", currentMessageContent);
    
    // 复制到剪贴板
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = currentMessageContent;
    
    // 跳转到淘宝
    NSString *taobaoScheme = @"taobao://";
    NSURL *taobaoURL = [NSURL URLWithString:taobaoScheme];
    
    [[UIApplication sharedApplication] openURL:taobaoURL options:@{} completionHandler:^(BOOL success) {
        if (success) {
            NSLog(@"[TaobaoJump] ✅ 成功跳转到淘宝");
        } else {
            NSLog(@"[TaobaoJump] ❌ 跳转失败，请确认已安装淘宝");
        }
    }];
}

// Hook 多个可能的微信菜单类，找出正确的类名

// 尝试 Hook WCActionSheet
%hook WCActionSheet

- (instancetype)init {
    NSLog(@"[TaobaoJump] 🔍 检测到 WCActionSheet init");
    return %orig;
}

- (void)show {
    NSLog(@"[TaobaoJump] 🔍 WCActionSheet show 被调用");
    %orig;
}

%end

// 尝试 Hook MMActionSheet  
%hook MMActionSheet

- (instancetype)init {
    NSLog(@"[TaobaoJump] 🔍 检测到 MMActionSheet init");
    return %orig;
}

- (void)showInView:(UIView *)view {
    NSLog(@"[TaobaoJump] 🔍 MMActionSheet showInView 被调用");
    %orig;
}

%end

// 尝试 Hook MMMenuController
%hook MMMenuController

- (instancetype)init {
    NSLog(@"[TaobaoJump] 🔍 检测到 MMMenuController init");
    return %orig;
}

%end

// 尝试 Hook UIAlertController (微信可能用这个)
%hook UIAlertController

- (void)addAction:(UIAlertAction *)action {
    if (self.preferredStyle == UIAlertControllerStyleActionSheet) {
        NSLog(@"[TaobaoJump] 🔍 UIAlertController ActionSheet 添加按钮: %@", action.title);
    }
    %orig;
}

%end

// Hook CommonMessageCellView 来获取消息内容
%hook CommonMessageCellView

- (void)setViewModel:(id)viewModel {
    %orig;
    
    if (!isTaobaoJumpEnabled()) {
        return;
    }
    
    // 获取消息内容
    if (viewModel && [viewModel respondsToSelector:@selector(messageWrap)]) {
        id messageWrap = [viewModel performSelector:@selector(messageWrap)];
        if (messageWrap && [messageWrap respondsToSelector:@selector(m_nsContent)]) {
            NSString *content = [messageWrap performSelector:@selector(m_nsContent)];
            if (content && content.length > 0) {
                currentMessageContent = content;
                NSLog(@"[TaobaoJump] 📝 保存消息内容: %@", content);
            }
        }
    }
}

// Hook 长按事件，记录日志
- (void)onLongTouch:(id)arg {
    NSLog(@"[TaobaoJump] 👆 检测到长按消息");
    
    // 打印当前视图的类名，帮助调试
    NSLog(@"[TaobaoJump] 📋 当前 Cell 类: %@", NSStringFromClass([self class]));
    
    %orig;
}

%end

%ctor {
    %init;
    NSLog(@"[TaobaoJump] 淘口令自动跳转功能已加载");
}
