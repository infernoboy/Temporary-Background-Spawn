#import <Preferences/PSListController.h>
#import <Preferences/PSEditableListController.h>
#import <Preferences/PSSpecifier.h>

@interface TSPreferencesListController : PSListController
-(void)openContactMe;
-(void)openSourceCodeURL;
@end

@interface TSTrackerController : PSEditableListController
@property (retain) NSUserDefaults *prefs;
@property (retain) NSUserDefaults *trackedItemsList;
@property (retain) NSBundle *prefBundle;

-(NSString*)localizedString:(NSString*)string;
@end
