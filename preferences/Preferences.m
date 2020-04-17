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
	self.prefs = [[NSUserDefaults alloc] initWithSuiteName:@"com.toggleable.tempspawn"];
	self.trackedItemsList = [[NSUserDefaults alloc] initWithSuiteName:@"com.toggleable.tempspawn~tracker"];
	self.prefBundle = [NSBundle bundleWithPath:@"/Library/PreferenceBundles/TempSpawnPreferences.bundle"];

	return [super init];
}

-(NSString*)localizedString:(NSString*)string {
	return [self.prefBundle localizedStringForKey:string value:string table:@"Preferences"];
}

-(void)removedSpecifier:(PSSpecifier*)specifier {
	[self.trackedItemsList removeObjectForKey:[specifier identifier]];
	[self.trackedItemsList removeObjectForKey:[[specifier identifier] stringByAppendingString:@"~displayName"]];
	
	[self removeSpecifierID:[[specifier identifier] stringByAppendingString:@"~description"] animated:YES];
}

-(void)clearAll:(PSSpecifier*)specifier {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:[self localizedString:@"CLEAR_ALL_MESSAGE"] preferredStyle:UIAlertControllerStyleAlert];

	UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:[self localizedString:@"CLEAR_ALL"] style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
		[[NSUserDefaults standardUserDefaults] removePersistentDomainForName:@"com.toggleable.tempspawn~tracker"];

		[self reloadSpecifiers];
	}];	

	[alert addAction:[UIAlertAction actionWithTitle:[self localizedString:@"CANCEL"] style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:defaultAction];

	[self presentViewController:alert animated:YES completion:nil];
}

-(id)specifiers {
	if(_specifiers == nil) {
		_specifiers = [NSMutableArray new];

		NSError *systemBlacklistError;

		NSArray *standardDefaults = [[[NSUserDefaults standardUserDefaults] dictionaryRepresentation] allKeys];

		NSDictionary *trackedItems = [self.trackedItemsList dictionaryRepresentation];
		NSDictionary *systemBlacklist = [NSDictionary dictionaryWithContentsOfURL:[NSURL URLWithString:@"file:///Library/PreferenceBundles/TempSpawnPreferences.bundle/system-blacklist.plist"] error:&systemBlacklistError];

		if (systemBlacklistError) {
			PSSpecifier *systemBlacklistErrorCell = [PSSpecifier preferenceSpecifierNamed:[self localizedString:@"SYSTEM_BLACKLIST_ERROR"] target:self set:nil get:nil detail:nil cell:PSTitleValueCell edit:nil];

			[_specifiers addObject:systemBlacklistErrorCell];

			return _specifiers;
		}

		NSArray *trackedItemKeys = [[trackedItems allKeys] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
			return ![standardDefaults containsObject:object] && ![(NSString*)object hasSuffix:@"~displayName"];
		}]];

		NSArray *sortedTrackedItems = [trackedItemKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
			NSNumber *aLaunches = [NSNumber numberWithInt:[trackedItems[a][@"backgroundLaunched"] integerValue]];
			NSNumber *bLaunches = [NSNumber numberWithInt:[trackedItems[b][@"backgroundLaunched"] integerValue]];

			return [bLaunches compare:aLaunches];
		}];


		for (NSString *key in sortedTrackedItems) {
			if ([systemBlacklist[key] boolValue] && ![self.prefs boolForKey:@"trackerShowSystem"])
				continue;

			NSString *appName = [trackedItems objectForKey:[key stringByAppendingString:@"~displayName"]];
			NSString *description = [NSString stringWithFormat:[self localizedString:@"TRACKED_APP_DESCRIPTION"], trackedItems[key][@"backgroundLaunched"], trackedItems[key][@"backgroundTerminated"], trackedItems[key][@"cancelledTermination"]];

			PSSpecifier *appGroup = [PSSpecifier groupSpecifierWithID:[key stringByAppendingString:@"~description"]];
			PSSpecifier *appCell = [PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"%@    (%@)", appName, key] target:self set:nil get:nil detail:nil cell:PSTitleValueCell edit:nil];

			[appGroup setProperty:description forKey:PSFooterTextGroupKey];

			[appCell setProperty:key forKey:PSIDKey];
			[appCell setProperty:NSStringFromSelector(@selector(removedSpecifier:)) forKey:PSDeletionActionKey];

			[_specifiers addObject:appGroup];
			[_specifiers addObject:appCell];
		}
	}

	if ([_specifiers count] > 0) {
		PSSpecifier *clearAllCell = [PSSpecifier preferenceSpecifierNamed:[self localizedString:@"CLEAR_ALL"] target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];

		clearAllCell->action = @selector(clearAll:);

		[_specifiers addObject:[PSSpecifier groupSpecifierWithID:@"clearAllGroup"]];
		[_specifiers addObject:clearAllCell];
	} else {
		PSSpecifier *noAppsGroup = [PSSpecifier groupSpecifierWithID:@"noApps"];

		[noAppsGroup setProperty:[self localizedString:@"NO_APPS_TRACKED"] forKey:PSFooterTextGroupKey];

		[_specifiers addObject:noAppsGroup];
	}

	return _specifiers;
}

@end
