/* LinphoneAppDelegate.m
 *
 * Copyright (C) 2009  Belledonne Comunications, Grenoble, France
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or   
 *  (at your option) any later version.                                 
 *                                                                      
 *  This program is distributed in the hope that it will be useful,     
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of      
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the       
 *  GNU General Public License for more details.                
 *                                                                      
 *  You should have received a copy of the GNU General Public License   
 *  along with this program; if not, write to the Free Software         
 *  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 */                                                                           

#import "linphoneAppDelegate.h"
#import "AddressBook/ABPerson.h"

#import "CoreTelephony/CTCallCenter.h"
#import "CoreTelephony/CTCall.h"

#import "AddressBookMap.h"
#import "Settings.h"
#import <RestKit/RestKit.h>

#include "LinphoneManager.h"
#include "LinphoneHelper.h"
#include "linphonecore.h"

#import "MappingProvider.h"
#import "Contact.h"
#import "User.h"


@implementation UILinphoneWindow

@end

@implementation LinphoneAppDelegate

@synthesize window = _window;
@synthesize started;


#pragma mark - Lifecycle Functions

- (id)init {
    self = [super init];
    if(self != nil) {
        self->started = FALSE;
    }
    return self;
}

- (void)dealloc {
	[super dealloc];
}


#pragma mark - 



- (void)applicationDidEnterBackground:(UIApplication *)application{
	[LinphoneHelper logc:LinphoneLoggerLog format:"applicationDidEnterBackground"];
	if(![LinphoneManager isLcReady]) return;
	[[LinphoneManager instance] enterBackgroundMode];
}

- (void)applicationWillResignActive:(UIApplication *)application {
	[LinphoneHelper logc:LinphoneLoggerLog format:"applicationWillResignActive"];
    if(![LinphoneManager isLcReady]) return;
    LinphoneCore* lc = [LinphoneManager getLc];
    LinphoneCall* call = linphone_core_get_current_call(lc);
	
	
    if (call){
		/* save call context */
		LinphoneManager* instance = [LinphoneManager instance];
		instance->currentCallContextBeforeGoingBackground.call = call;
		instance->currentCallContextBeforeGoingBackground.cameraIsEnabled = linphone_call_camera_enabled(call);
    
		const LinphoneCallParams* params = linphone_call_get_current_params(call);
		if (linphone_call_params_video_enabled(params)) {
			linphone_call_enable_camera(call, false);
		}
	}
    
    if (![[LinphoneManager instance] resignActive]) {

    }
    
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
	[LinphoneHelper logc:LinphoneLoggerLog format:"applicationDidBecomeActive"];
    [self startApplication];
    
	[[LinphoneManager instance] becomeActive];
    
    
    LinphoneCore* lc = [LinphoneManager getLc];
    LinphoneCall* call = linphone_core_get_current_call(lc);
    
	if (call){
		LinphoneManager* instance = [LinphoneManager instance];
		if (call == instance->currentCallContextBeforeGoingBackground.call) {
			const LinphoneCallParams* params = linphone_call_get_current_params(call);
			if (linphone_call_params_video_enabled(params)) {
				linphone_call_enable_camera(
                                        call, 
                                        instance->currentCallContextBeforeGoingBackground.cameraIsEnabled);
			}
			instance->currentCallContextBeforeGoingBackground.call = 0;
		}
	}
}



- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [[UIApplication sharedApplication] registerForRemoteNotificationTypes:UIRemoteNotificationTypeAlert|UIRemoteNotificationTypeSound|UIRemoteNotificationTypeBadge];
    
	//work around until we can access lpconfig without linphonecore
	NSDictionary *appDefaults = [NSDictionary dictionaryWithObjectsAndKeys:
                                 @"YES", @"start_at_boot_preference",
								 @"YES", @"backgroundmode_preference",
#ifdef DEBUG
								 @"YES",@"debugenable_preference",
#else
								 @"NO",@"debugenable_preference",
#endif
                                 nil];
	[[NSUserDefaults standardUserDefaults] registerDefaults:appDefaults];
	
    if ([[UIDevice currentDevice] respondsToSelector:@selector(isMultitaskingSupported)]
		&& [UIApplication sharedApplication].applicationState ==  UIApplicationStateBackground
        && (![[NSUserDefaults standardUserDefaults] boolForKey:@"start_at_boot_preference"] ||
            ![[NSUserDefaults standardUserDefaults] boolForKey:@"backgroundmode_preference"])) {
            // autoboot disabled, doing nothing
            return YES;
        }
    
    [self setupRestKit];
     
    [self startApplication];
	NSDictionary *remoteNotif =[launchOptions objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey];
    if (remoteNotif){
		[LinphoneHelper log:LinphoneLoggerLog format:@"PushNotification from launch received."];
		[self processRemoteNotification:remoteNotif];
	}

    return YES;
}

- (void)setupRestKit{
    // Set base URL
    RKObjectManager *objectManager = [RKObjectManager managerWithBaseURL:[NSURL URLWithString:@"https://api.zirgoo.com/"]];
    
    // Set HTTP parameters
    [objectManager.HTTPClient setParameterEncoding:AFJSONParameterEncoding];
    [objectManager.HTTPClient registerHTTPOperationClass:[AFJSONRequestOperation class]];
    [objectManager.HTTPClient setDefaultHeader:@"Accept" value:@"application/json"];
    [objectManager setRequestSerializationMIMEType:RKMIMETypeJSON];
    NSIndexSet *statusCodeSet = RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful);
    
    // Register response mapping
    [objectManager addResponseDescriptor:[RKResponseDescriptor responseDescriptorWithMapping:[MappingProvider statusMapping]
                                                                                      method:RKRequestMethodGET
                                                                                 pathPattern:nil
                                                                                     keyPath:@""
                                                                                 statusCodes:statusCodeSet]];

    [objectManager addResponseDescriptor:[RKResponseDescriptor responseDescriptorWithMapping:[MappingProvider userMapping]
                                                                                      method:RKRequestMethodGET
                                                                                 pathPattern:nil
                                                                                     keyPath:@"user"
                                                                                 statusCodes:statusCodeSet]];

    [objectManager addResponseDescriptor:[RKResponseDescriptor responseDescriptorWithMapping:[MappingProvider userMapping]
                                                                                      method:RKRequestMethodGET
                                                                                 pathPattern:nil
                                                                                     keyPath:@"users"
                                                                                 statusCodes:statusCodeSet]];

    [RKObjectManager setSharedManager:objectManager];
}

- (void)startApplication {
    // Restart Linphone Core if needed
    if(![LinphoneManager isLcReady]) {
        [[LinphoneManager instance]	startLibLinphone];
    }
    if([LinphoneManager isLcReady]) {
        
        // Only execute one time at application start
        if(!started) {
            started = TRUE;
            [AddressBookMap reload];
        }
        
        // Set factory default settings at the first launch
        if ([Settings isFirstAlreadyLaunched] == NO) {
            
            [Settings setAutoClearCallHistoryEnabled:YES];
            [Settings setAutoClearCallHistory:OneMinute];
            
            [Settings setAutoClearChatHistoryEnabled:YES];
            [Settings setAutoClearChatHistory:OneMinute];
            
            [Settings setFirstAlreadyLaunched:YES];
        }
    }
}

- (void)applicationWillTerminate:(UIApplication *)application {
	
}

- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url {
    [self startApplication];
    
    if([LinphoneManager isLcReady]) {
        /* CHC //
        if([[url scheme] isEqualToString:@"sip"]) {
            // Go to ChatRoom view
            DialerViewController *controller = DYNAMIC_CAST([[PhoneMainView instance] changeCurrentView:[DialerViewController compositeViewDescription]], DialerViewController);
            if(controller != nil) {
                [controller setAddress:[url absoluteString]];
            }
        }
         */
    }
	return YES;
}

- (void)processRemoteNotification:(NSDictionary*)userInfo{
	NSDictionary *aps = [userInfo objectForKey:@"aps"];
    if(aps != nil) {
        NSDictionary *alert = [aps objectForKey:@"alert"];
        if(alert != nil) {
            NSString *loc_key = [alert objectForKey:@"loc-key"];
			/*if we receive a remote notification, it is because our TCP background socket was no more working.
			 As a result, break it and refresh registers in order to make sure to receive incoming INVITE or MESSAGE*/
			LinphoneCore *lc = [LinphoneManager getLc];
			linphone_core_set_network_reachable(lc, FALSE);
			linphone_core_set_network_reachable(lc, TRUE);
            if(loc_key != nil) {
                if([loc_key isEqualToString:@"IM_MSG"]) {
                    // CHC // [[PhoneMainView instance] addInhibitedEvent:kLinphoneTextReceived];
                    // CHC // [[PhoneMainView instance] changeCurrentView:[ChatViewController compositeViewDescription]];
                } else if([loc_key isEqualToString:@"IC_MSG"]) {
                    //it's a call
					NSString *callid=[userInfo objectForKey:@"call-id"];
                    if (callid)
						[[LinphoneManager instance] enableAutoAnswerForCallId:callid];
					else
						[LinphoneHelper log:LinphoneLoggerError format:@"PushNotification: does not have call-id yet, fix it !"];
                }
            }
        }
    }
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
	[LinphoneHelper log:LinphoneLoggerLog format:@"PushNotification: Receive %@", userInfo];
	[self processRemoteNotification:userInfo];
}

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification {
    if([notification.userInfo objectForKey:@"callId"] != nil) {
        [[LinphoneManager instance] acceptCallForCallId:[notification.userInfo objectForKey:@"callId"]];
    } else if([notification.userInfo objectForKey:@"chat"] != nil) {
        /* CHC //
        NSString *remoteContact = (NSString*)[notification.userInfo objectForKey:@"chat"];
        // Go to ChatRoom view
        [[PhoneMainView instance] changeCurrentView:[ChatViewController compositeViewDescription]];
        ChatRoomViewController *controller = DYNAMIC_CAST([[PhoneMainView instance] changeCurrentView:[ChatRoomViewController compositeViewDescription] push:TRUE], ChatRoomViewController);
        if(controller != nil) {
            [controller setRemoteAddress:remoteContact];
        }
         */
    } else if([notification.userInfo objectForKey:@"callLog"] != nil) {
        NSString *callLog = (NSString*)[notification.userInfo objectForKey:@"callLog"];
        LinphoneCallLog* theLog = NULL;
        const MSList * logs = linphone_core_get_call_logs([LinphoneManager getLc]);
        while(logs != NULL) {
            LinphoneCallLog* log = (LinphoneCallLog *) logs->data;
            if([callLog isEqualToString:[NSString stringWithUTF8String:linphone_call_log_get_call_id(log)]]) {
                theLog = log;
                break;
            }
            logs = logs->next;
        }
        if(theLog != NULL) {
            // Go to HistoryDetails view
            /* CHC //
            [[PhoneMainView instance] changeCurrentView:[HistoryViewController compositeViewDescription]];
            HistoryDetailsViewController *controller = DYNAMIC_CAST([[PhoneMainView instance] changeCurrentView:[HistoryDetailsViewController compositeViewDescription] push:TRUE], HistoryDetailsViewController);
            if(controller != nil) {
                [controller setCallLog:theLog];
            }
             */
        }
    }
}


#pragma mark - PushNotification Functions

- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken {
    [LinphoneHelper log:LinphoneLoggerLog format:@"PushNotification: Token %@", deviceToken];
    [[LinphoneManager instance] setPushNotificationToken:deviceToken];
}

- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error {
    [LinphoneHelper log:LinphoneLoggerError format:@"PushNotification: Error %@", [error localizedDescription]];
    [[LinphoneManager instance] setPushNotificationToken:nil];
}

@end
