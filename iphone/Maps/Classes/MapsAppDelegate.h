#import "DownloadIndicatorProtocol.h"
#import "MWMNavigationController.h"
#import <UserNotifications/UserNotifications.h>
#import <FirebaseMessaging/FirebaseMessaging.h>

@class MapViewController;
@class MWMCarPlayService;

NS_ASSUME_NONNULL_BEGIN

@interface MapsAppDelegate : UIResponder<UIApplicationDelegate,
UNUserNotificationCenterDelegate,DownloadIndicatorProtocol,FIRMessagingDelegate>
{
  NSInteger m_activeDownloadsCounter;
  UIBackgroundTaskIdentifier m_backgroundTask;
}

@property(nonatomic) UIWindow * window;

@property(nonatomic, readonly) MWMCarPlayService *carplayService API_AVAILABLE(ios(12.0));
@property(nonatomic, readonly) MapViewController * mapViewController;
@property(nonatomic, readonly) BOOL isDrapeEngineCreated;

+ (MapsAppDelegate *)theApp;

- (void)enableStandby;
- (void)disableStandby;

+ (void)customizeAppearance;
+ (void)customizeAppearanceForNavigationBar:(UINavigationBar *)navigationBar;

- (void)disableDownloadIndicator;
- (void)enableDownloadIndicator;

- (void)showMap;

- (NSUInteger)badgeNumber;

+ (BOOL)isTestsEnvironment;

@end

NS_ASSUME_NONNULL_END
