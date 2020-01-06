#import "Tweak.h"

#if DEBUG
#define NSLog(args...) NSLog(@"[TempSpawn] "args)
#else
#define NSLog(...);
#endif

extern "C" void BKSTerminateApplicationForReasonAndReportWithDescription(NSString *bundleIdentifier, int reasonID, bool report, NSString *description);

NSString *blacklistPlist = @"file:///var/mobile/Library/Preferences/com.toggleable.tempspawn~blacklist.plist";

long terminateDelay = 30.0;

TempSpawn *tempSpawn;

static void blacklistChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
	[tempSpawn loadBlacklist];

}


@implementation TempSpawnProcessState
-(TempSpawnProcessState*)initWithProcessState:(SBApplicationProcessState*)processState app:(SBApplication*)app {
	self = [super init];

	_launchedInBackground = NO;

	self.seen = NO;
	self.processState = processState;
	self.app = app;

	return self;
}

-(void)setLaunchedInBackground:(BOOL)launchedInBackground {
	_launchedInBackground = launchedInBackground;
	
	self.seen = YES;
}
@end


@implementation TempSpawn
-(TempSpawn*)init {
	self.terminationTimers = [NSMutableDictionary dictionary];
	self.processStates = [NSMutableDictionary dictionary];

	[self loadBlacklist];

	return self;
}

-(void)addObservers {
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationProcessStateDidChange:) name:@"SBApplicationProcessStateDidChange" object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(callStatusChanged:) name:@"TUCallCenterCallStatusChangedNotification" object:nil];
	
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)blacklistChanged, CFSTR("com.toggleable.tempspawn~blacklistChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}

-(void)loadBlacklist {
	NSError *error;

	self.blacklist = [NSDictionary dictionaryWithContentsOfURL:[NSURL URLWithString:blacklistPlist] error:&error];

	if (error) {
		NSLog(@"Blacklist not found or corrupted.");

		self.blacklist = @{};
	}

	NSLog(@"Blacklist loaded: %@", self.blacklist);
}

-(BOOL)isBlacklisted:(NSString*)bundleIdentifier {
	return [[self.blacklist objectForKey:bundleIdentifier] boolValue];
}

-(void)callStatusChanged:(id)notification {
	TUProxyCall *proxyCall = (TUProxyCall*)[notification object];

	NSString *callAppBundleIdentifier = [[proxyCall backingProvider] bundleIdentifier];

	if (callAppBundleIdentifier) {
		NSLog(@"Call status for %@: %i", callAppBundleIdentifier, [proxyCall callStatus]);

		TempSpawnProcessState *previousProcessState = self.processStates[callAppBundleIdentifier];

		if (previousProcessState) {
			if ([proxyCall callStatus] == 4) // ringing
				[self cancelTerminationTimer:callAppBundleIdentifier];
			else if ([proxyCall callStatus] == 6 && [previousProcessState launchedInBackground]) // disconnected
				[self terminateAppNow:callAppBundleIdentifier withReason:@"call disconnected"];
		}
	}
}

-(void)showLaunchedInBackgroundNotification:(NSString*)bundleIdentifier {
	[%c(CPNotification) showAlertWithTitle:nil
		message:@"Launched in background, will automatically terminate soon."
		userInfo:nil
		badgeCount:nil
		soundName:nil
		delay:1
		repeats:NO
		bundleId:bundleIdentifier
	];
}

-(void)applicationProcessStateDidChange:(id)notification {
	if ([notification object]) {
		SBApplication *app = (SBApplication*)[notification object];

		@try {
			if ([app isSystemApplication])
				return; 
		}
		@catch (NSException *exception) {
			return;
		}

		if ([[app processState] isRunning]) {
			TempSpawnProcessState *previousProcessState = self.processStates[[app bundleIdentifier]];

			if ([[app processState] taskState] != 3) { // suspended
				// NSLog(@"processState: %@ is %lld - taskState: %lld", [app bundleIdentifier], [[app processState] visibility], [[app processState] taskState]);

				if (previousProcessState) {
					// NSLog(@"previousProcessState for %@: %@", [app bundleIdentifier], previousProcessState);

					if (![previousProcessState launchedInBackground] && [previousProcessState seen]) {
						NSLog(@"Ignoring already seen app: %@", [app bundleIdentifier]);
						return;
					}

					if ([[previousProcessState processState] visibility] == 0 && [[app processState] visibility] == 1) {
						NSLog(@"Launched in background from unknown: %@", [app bundleIdentifier]);

						previousProcessState.launchedInBackground = YES;

						#if DEBUG
						[self showLaunchedInBackgroundNotification:[app bundleIdentifier]];
						#endif

						[self terminateAppSoon:[app bundleIdentifier]];
					} else if ([[app processState] visibility] == 2) {
						if (previousProcessState.launchedInBackground) {
							NSLog(@"Moved to foreground: %@", [app bundleIdentifier]);

							[self cancelTerminationTimer:[app bundleIdentifier]];
						}

						previousProcessState.launchedInBackground = NO;
					}
				} else
					previousProcessState = [[TempSpawnProcessState alloc] initWithProcessState:[app processState] app:app];

				if ([[app processState] visibility] == 1 && ![previousProcessState launchedInBackground]) {
					NSLog(@"Launched in background: %@", [app bundleIdentifier]);

					previousProcessState.launchedInBackground = YES;

					#if DEBUG
					[self showLaunchedInBackgroundNotification:[app bundleIdentifier]];
					#endif

					[self terminateAppSoon:[app bundleIdentifier]];
				}
			} else if ([previousProcessState launchedInBackground]) {
				NSLog(@"App was launched in background, but now suspended: %@", [app bundleIdentifier]);

				[self terminateAppNow:[app bundleIdentifier] withReason:@"background activity completed"];
			}

			previousProcessState.processState = [app processState];
			previousProcessState.app = app;

			self.processStates[[app bundleIdentifier]] = previousProcessState;
		} else {
			NSLog(@"Terminated: %@", [app bundleIdentifier]);

			[self.processStates removeObjectForKey:[app bundleIdentifier]];
		}
	}
}

-(void)terminateAppFromTimer:(NSTimer*)timer {
	[self terminateAppNow:timer.userInfo withReason:@"background time expired"];
}

-(void)cancelTerminationTimer:(NSString*)bundleIdentifier {
	NSTimer *timer = self.terminationTimers[bundleIdentifier];

	if (timer) {
		NSLog(@"Cancelling termination timer: %@", bundleIdentifier);

		[timer invalidate];
		[self.terminationTimers removeObjectForKey:bundleIdentifier];
	}
}

-(void)terminateAppSoon:(NSString*)bundleIdentifier {
	if ([self isBlacklisted:bundleIdentifier]) {
		NSLog(@"terminateAppSoon blacklisted: %@", bundleIdentifier);
		return;
	}

	NSLog(@"Terminating soon: %@", bundleIdentifier);

	NSTimer *timer = self.terminationTimers[bundleIdentifier];

	if (timer)
		[timer invalidate];
	
	self.terminationTimers[bundleIdentifier] = [NSTimer scheduledTimerWithTimeInterval:terminateDelay target:self selector:@selector(terminateAppFromTimer:) userInfo:bundleIdentifier repeats:NO];
}

-(void)terminateAppNow:(NSString*)bundleIdentifier withReason:(NSString*)reason {
	if ([self isBlacklisted:bundleIdentifier]) {
		NSLog(@"terminateAppNow blacklisted: %@", bundleIdentifier);
		return;
	}

	TempSpawnProcessState *previousProcessState = self.processStates[bundleIdentifier];
	
	if (previousProcessState && ([previousProcessState.app isPlayingAudio] || [previousProcessState.app isNowRecordingApplication] || [previousProcessState.app isConnectedToExternalAccessory])) {
		NSLog(@"Refusing to terminate %@ because audio or accessory is active.", bundleIdentifier);
		return;
	}
	
	NSLog(@"Terminating %@ due to %@", bundleIdentifier, reason);

	[self cancelTerminationTimer:bundleIdentifier];

	BKSTerminateApplicationForReasonAndReportWithDescription(bundleIdentifier, 1, NO, [NSString stringWithFormat:@"[TempSpawn] %@", reason]);
}
@end

%ctor {
	tempSpawn = [[TempSpawn alloc] init];

	[tempSpawn addObservers];
}
