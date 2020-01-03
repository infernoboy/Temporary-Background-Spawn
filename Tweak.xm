#import "Tweak.h"

#if DEBUG
#define NSLog(args...) NSLog(@"[TempSpawn] "args)
#else
#define NSLog(...);
#endif

extern "C" void BKSTerminateApplicationForReasonAndReportWithDescription(NSString *bundleIdentifier, int reasonID, bool report, NSString *description);

long terminateDelay = 30.0;

TempSpawn *tempSpawn;


@implementation TempSpawnProcessState
-(TempSpawnProcessState*)initWithProcessState:(SBApplicationProcessState*)processState {
	self = [super init];

	_launchedInBackground = NO;

	self.seen = NO;
	self.processState = processState;

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

	return self;
}

-(void)addObservers {
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationProcessStateDidChange:) name:@"SBApplicationProcessStateDidChange" object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(callStatusChanged:) name:@"TUCallCenterCallStatusChangedNotification" object:nil];
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
	if ([notification object] && [NSStringFromClass([[notification object] class]) isEqualToString:@"SBApplication"]) {
		SBApplication *app = (SBApplication*)[notification object];

		if ([app isSystemApplication])
			return; 

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
					previousProcessState = [[TempSpawnProcessState alloc] initWithProcessState:[app processState]];

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
	NSLog(@"Terminating soon: %@", bundleIdentifier);

	NSTimer *timer = self.terminationTimers[bundleIdentifier];

	if (timer)
		[timer invalidate];
	
	self.terminationTimers[bundleIdentifier] = [NSTimer scheduledTimerWithTimeInterval:terminateDelay target:self selector:@selector(terminateAppFromTimer:) userInfo:bundleIdentifier repeats:NO];
}

-(void)terminateAppNow:(NSString*)bundleIdentifier withReason:(NSString*)reason {
	NSLog(@"Terminating %@ due to %@", bundleIdentifier, reason);

	[self cancelTerminationTimer:bundleIdentifier];

	BKSTerminateApplicationForReasonAndReportWithDescription(bundleIdentifier, 1, NO, [NSString stringWithFormat:@"[TempSpawn] %@", reason]);
}
@end

%ctor {
	tempSpawn = [[TempSpawn alloc] init];

	[tempSpawn addObservers];
}
