//
// Copyright (c) 2014 Mixpanel. All rights reserved.

#import "MPABTestDesignerSnapshotRequestMessage.h"
#import "MPABTestDesignerConnection.h"
#import "MPABTestDesignerSnapshotResponseMessage.h"
#import "MPApplicationStateSerializer.h"
#import "MPClassDescription.h"

NSString * const MPABTestDesignerSnapshotRequestMessageType = @"snapshot_request";

static NSString * const kSnapshotClassDescriptionsKey = @"snapshot_class_descriptions";

@implementation MPABTestDesignerSnapshotRequestMessage

+ (instancetype)message
{
    return [[self alloc] initWithType:@"snapshot_request"];
}

- (NSDictionary *)configuration
{
    return [self payloadObjectForKey:@"config"];
}

- (NSOperation *)responseCommandWithConnection:(MPABTestDesignerConnection *)connection
{
    NSArray *classes = self.configuration[@"classes"];
    __block NSArray *classDescriptions = classes ? [self classDescriptionsFromArray:classes] : nil;

    __weak MPABTestDesignerConnection *weak_connection = connection;
    NSOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
        __strong MPABTestDesignerConnection *conn = weak_connection;

        // Update the class descriptions in the connection session if provided as part of the message.
        if (classDescriptions)
        {
            [connection setSessionObject:classDescriptions forKey:kSnapshotClassDescriptionsKey];
        }
        else
        {
            // Get the class descriptions from the connection session store.
            classDescriptions = [connection sessionObjectForKey:kSnapshotClassDescriptionsKey];
        }
        
        MPApplicationStateSerializer *serializer = [[MPApplicationStateSerializer alloc] initWithApplication:[UIApplication sharedApplication]
                                                                                           classDescriptions:classDescriptions];

        __block UIImage *screenshot = nil;
        __block NSDictionary *serializedObjects = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{

            // TODO: we should probably be serializing an object graph from the UIApplication instance down and thus capturing all windows,
            // the keyWindow and all the relevant view controllers from the rootViewController of each window down.  Some applications
            // exist on multiple screens (apps that support HDMI output or AirPlay) and a screen can have multiple windows.  Eg, I think
            // UIAlertView exists in a separate window.  I think the status bar is also in a separate window.
            // For applications with multiple screens/windows this would mean capturing multiple screen shots too.

            screenshot = [serializer screenshotImageForWindowAtIndex:0];
            serializedObjects = [serializer objectHierarchyForWindowAtIndex:0];

        });

        MPABTestDesignerSnapshotResponseMessage *snapshotMessage = [MPABTestDesignerSnapshotResponseMessage message];
        snapshotMessage.screenshot = screenshot;
        snapshotMessage.serializedObjects = serializedObjects;
        [conn sendMessage:snapshotMessage];
    }];

    return operation;
}

- (NSArray *)classDescriptionsFromArray:(NSArray *)classes
{
    NSParameterAssert(classes != nil);

    NSMutableDictionary *classDescriptions = [[NSMutableDictionary alloc] init];
    for (NSDictionary *dictionary in classes)
    {
        NSString *superclassName = dictionary[@"superclass"];
        MPClassDescription *superclassDescription = superclassName ? classDescriptions[superclassName] : nil;
        MPClassDescription *classDescription = [[MPClassDescription alloc] initWithSuperclassDescription:superclassDescription
                                                                                              dictionary:dictionary];

        [classDescriptions setObject:classDescription forKey:classDescription.name];
    }

    return [classDescriptions allValues];
}

@end
