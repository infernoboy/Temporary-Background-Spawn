#import "Preferences.h"

@implementation TSPreferencesListController

-(instancetype)init {
	return [super init];
}

-(id)specifiers {
	if(_specifiers == nil)
		_specifiers = [[self loadSpecifiersFromPlistName:@"Preferences" target:self] retain];

	return _specifiers;
}

-(void)openContactMe {
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"mailto:travis@toggleable.com?subject=Temporary%20Background%20Spawn"] options:@{} completionHandler:nil];
}

-(void)openSourceCodeURL {
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/infernoboy/Temporary-Background-Spawn"] options:@{} completionHandler:nil];
}

@end


@implementation TSTrackerController

-(instancetype)init {
	return [super init];
}

-(id)specifiers {
	if(_specifiers == nil) {
		_specifiers = [NSMutableArray new];

		NSError *error;

		NSDictionary *trackedItems = [NSDictionary dictionaryWithContentsOfURL:[NSURL URLWithString:@"file:///private/var/mobile/Library/Preferences/com.toggleable.tempspawn~tracker.plist"] error:&error];

		if (error) {
			PSSpecifier *errorCell = [PSSpecifier preferenceSpecifierNamed:@"Tracked items list not found or corrupted." target:self set:nil get:nil detail:nil cell:PSTitleValueCell edit:nil];

			[_specifiers addObject:errorCell];

			return _specifiers;
		}

		PSSpecifier *helpCell = [PSSpecifier preferenceSpecifierNamed:nil target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];

		[helpCell setProperty:@"Only tracks background launches." forKey:@"footerText"];

		[_specifiers addObject:helpCell];

		NSArray *trackedItemKeysAll = [trackedItems allKeys];

		NSPredicate *trackedItemsPredicate = [NSPredicate predicateWithFormat:@"NOT (SELF endswith %@)", @"~displayName"];

		NSArray *trackedItemKeys = [trackedItemKeysAll filteredArrayUsingPredicate:trackedItemsPredicate];

		NSArray *sortedTrackedItems = [trackedItemKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
			NSNumber *aLaunches = [NSNumber numberWithInt:[trackedItems[a][@"backgroundLaunched"] integerValue]];
			NSNumber *bLaunches = [NSNumber numberWithInt:[trackedItems[b][@"backgroundLaunched"] integerValue]];

			return [bLaunches compare:aLaunches];
		}];


		for (NSString *key in sortedTrackedItems) {
			NSString *appName = [trackedItems objectForKey:[key stringByAppendingString:@"~displayName"]];
			NSString *description = [NSString stringWithFormat:@"Launches: %@, terminations: %@, cancelled terminations: %@", trackedItems[key][@"backgroundLaunched"], trackedItems[key][@"backgroundTerminated"], trackedItems[key][@"cancelledTermination"]];

			PSSpecifier *descriptionCell = [PSSpecifier preferenceSpecifierNamed:nil target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
			PSSpecifier *appCell = [PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"%@    (%@)", appName, key] target:self set:nil get:nil detail:nil cell:PSTitleValueCell edit:nil];

			[descriptionCell setProperty:description forKey:@"footerText"];

			[_specifiers addObject:descriptionCell];
			[_specifiers addObject:appCell];
		}
	}

	return _specifiers;
}

@end
