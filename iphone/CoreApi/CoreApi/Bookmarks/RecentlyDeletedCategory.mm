#import "RecentlyDeletedCategory+Core.h"

#include <chrono>
#include <platform/platform_ios.h>

@implementation RecentlyDeletedCategory

@end

@implementation RecentlyDeletedCategory (Core)

- (instancetype)initWithCategoryData:(kml::CategoryData)data  filePath:(std::string)filePath {
  self = [super init];
  if (self) {
    auto const name = data.m_name[kml::kDefaultLangCode];
    _title = [NSString stringWithCString:name.c_str() encoding:NSUTF8StringEncoding];
    auto const pathString = [NSString stringWithCString:filePath.c_str() encoding:NSUTF8StringEncoding];
    _fileURL = [NSURL URLWithString:pathString];

    NSTimeInterval creationTime = Platform::GetFileCreationTime(filePath);
    _deletionDate = [NSDate dateWithTimeIntervalSince1970:creationTime];
  }
  return self;
}

@end
