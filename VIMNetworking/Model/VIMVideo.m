//
//  VIMVideo.m
//  VIMNetworking
//
//  Created by Kashif Mohammad on 3/23/13.
//  Copyright (c) 2014-2015 Vimeo (https://vimeo.com)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import "VIMVideo.h"

#import "VIMUser.h"
#import "VIMPicture.h"
#import "VIMVideoFile.h"
#import "VIMConnection.h"
#import "VIMInteraction.h"
#import "VIMPictureCollection.h"
#import "VIMPrivacy.h"
#import "VIMAppeal.h"
#import "NSString+MD5.h"
#import "VIMObjectMapper.h"
#import "VIMTag.h"
#import "VIMVideoLog.h"
#import "VIMCategory.h"

NSString *VIMContentRating_Language = @"language";
NSString *VIMContentRating_Drugs = @"drugs";
NSString *VIMContentRating_Violence = @"violence";
NSString *VIMContentRating_Nudity = @"nudity";
NSString *VIMContentRating_Unrated = @"unrated";
NSString *VIMContentRating_Safe = @"safe";

@interface VIMVideo ()

@property (nonatomic, strong) NSDictionary *metadata;
@property (nonatomic, strong) NSDictionary *connections;
@property (nonatomic, strong) NSDictionary *interactions;

@end

@implementation VIMVideo

#pragma mark - Accessors

- (NSString *)objectID
{
    NSAssert([self.uri length] > 0, @"Object does not have a uri, cannot generate objectID");
    
    return [self.uri MD5];
}

#pragma mark - Public API

- (VIMConnection *)connectionWithName:(NSString *)connectionName
{
    return [self.connections objectForKey:connectionName];
}

- (VIMInteraction *)interactionWithName:(NSString *)name
{
    return [self.interactions objectForKey:name];
}

- (NSDateFormatter *)dateFormatter
{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	[dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZZZZ"];
    return dateFormatter;
}

#pragma mark - VIMMappable

- (NSDictionary *)getObjectMapping
{
    return @{@"description": @"videoDescription",
             @"pictures": @"pictureCollection"};
}

- (Class)getClassForCollectionKey:(NSString *)key
{
    if([key isEqualToString:@"files"])
        return [VIMVideoFile class];
    
    if ([key isEqualToString:@"tags"])
        return [VIMTag class];
    
    if ([key isEqualToString:@"categories"])
        return [VIMCategory class];
    
	return nil;
}

- (Class)getClassForObjectKey:(NSString *)key
{
    if( [key isEqualToString:@"pictures"] )
        return [VIMPictureCollection class];

    if([key isEqualToString:@"user"])
        return [VIMUser class];

	if([key isEqualToString:@"metadata"])
        return [NSMutableDictionary class];

    if([key isEqualToString:@"privacy"])
        return [VIMPrivacy class];
    
    if([key isEqualToString:@"appeal"])
        return [VIMAppeal class];
    
    if( [key isEqualToString:@"log"] )
        return [VIMVideoLog class];

    return nil;
}

- (void)didFinishMapping
{
    if ([self.pictureCollection isEqual:[NSNull null]])
    {
        self.pictureCollection = nil;
    }

    // This is a temporary fix until we implement model versioning for cached JSON [AH]
    [self checkIntegrityOfPictureCollection];

    [self parseConnections];
    [self parseInteractions];
    [self formatCreatedTime];
    [self formatModifiedTime];
    
    id ob = [self.stats valueForKey:@"plays"];
    if (ob && [ob isKindOfClass:[NSNumber class]])
    {
        self.numPlays = ob;
    }
    
    [self setVideoStatus];
}

#pragma mark - Model Versioning

// This is only called for unarchived model objects [AH]

- (void)upgradeFromModelVersion:(NSUInteger)fromVersion toModelVersion:(NSUInteger)toVersion
{
    if (fromVersion == 2 && toVersion == 3)
    {
        [self checkIntegrityOfPictureCollection];
    }
}

- (void)checkIntegrityOfPictureCollection
{
    if ([self.pictureCollection isKindOfClass:[NSArray class]])
    {
        NSArray *pictures = (NSArray *)self.pictureCollection;
        self.pictureCollection = [VIMPictureCollection new];
        
        if ([pictures count])
        {
            if ([[pictures firstObject] isKindOfClass:[VIMPicture class]])
            {
                self.pictureCollection.pictures = pictures;
            }
            else if ([[pictures firstObject] isKindOfClass:[NSDictionary class]])
            {
                NSMutableArray *pictureObjects = [NSMutableArray array];
                for (NSDictionary *dictionary in pictures)
                {
                    VIMPicture *picture = [[VIMPicture alloc] initWithKeyValueDictionary:dictionary];
                    [pictureObjects addObject:picture];
                }
                
                self.pictureCollection.pictures = pictureObjects;
            }
        }
    }
}

#pragma mark - Parsing Helpers

- (void)parseConnections
{
    NSMutableDictionary *connections = [NSMutableDictionary dictionary];
    
    NSDictionary *dict = [self.metadata valueForKey:@"connections"];
    if([dict isKindOfClass:[NSDictionary class]])
    {
        for(NSString *key in [dict allKeys])
        {
            NSDictionary *value = [dict valueForKey:key];
            if([value isKindOfClass:[NSDictionary class]])
            {
                VIMConnection *connection = [[VIMConnection alloc] initWithKeyValueDictionary:value];
                if([connection respondsToSelector:@selector(didFinishMapping)])
                    [connection didFinishMapping];
                
                [connections setObject:connection forKey:key];
            }
        }
    }
    
    self.connections = connections;
}

- (void)parseInteractions
{
    NSMutableDictionary *interactions = [NSMutableDictionary dictionary];
    
    NSDictionary *dict = [self.metadata valueForKey:@"interactions"];
    if([dict isKindOfClass:[NSDictionary class]])
    {
        for(NSString *key in [dict allKeys])
        {
            NSDictionary *value = [dict valueForKey:key];
            if([value isKindOfClass:[NSDictionary class]])
            {
                VIMInteraction *interaction = [[VIMInteraction alloc] initWithKeyValueDictionary:value];
                if([interaction respondsToSelector:@selector(didFinishMapping)])
                    [interaction didFinishMapping];
                
                [interactions setObject:interaction forKey:key];
            }
        }
    }
    
    self.interactions = interactions;
}

- (void)formatCreatedTime
{
    if ([self.createdTime isKindOfClass:[NSString class]])
    {
        self.createdTime = [[VIMModelObject dateFormatter] dateFromString:(NSString *)self.createdTime];
    }
}

- (void)formatModifiedTime
{
    if ([self.modifiedTime isKindOfClass:[NSString class]])
    {
        self.modifiedTime = [[VIMModelObject dateFormatter] dateFromString:(NSString *)self.modifiedTime];
    }
}

- (void)setVideoStatus
{
    NSDictionary *statusDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
                                      [NSNumber numberWithInt:VIMVideoProcessingStatusAvailable], @"available",
                                      [NSNumber numberWithInt:VIMVideoProcessingStatusUploading], @"uploading",
                                      [NSNumber numberWithInt:VIMVideoProcessingStatusTranscoding], @"transcoding",
                                      [NSNumber numberWithInt:VIMVideoProcessingStatusUploadingError], @"uploading_error",
                                      [NSNumber numberWithInt:VIMVideoProcessingStatusTranscodingError], @"transcoding_error",
                                      nil];
    
    self.videoStatus = [[statusDictionary objectForKey:self.status] intValue];
}

# pragma mark - Helpers

- (BOOL)canComment
{
    NSString *privacy = self.privacy.comments;
    if( [privacy isEqualToString:VIMPrivacy_Public] )
    {
        return YES;
    }
    else if( [privacy isEqualToString:VIMPrivacy_Private] )
    {
        return NO;
    }
    else
    {
        VIMConnection *connection = [self connectionWithName:VIMConnectionNameComments];
        
        return (connection && [connection canPost]);
    }
}

- (BOOL)canLike
{
    VIMInteraction *interaction = [self interactionWithName:VIMInteractionNameLike];
    
    return interaction && [interaction.uri length];
}

- (BOOL)canViewComments
{
    return [self connectionWithName:VIMConnectionNameComments].uri != nil;
}

- (BOOL)isVOD
{
    NSString *privacy = self.privacy.view;
    return [privacy isEqualToString:VIMPrivacy_VOD];
}

- (BOOL)isPrivate
{
    NSString *privacy = self.privacy.view;
    return ![privacy isEqualToString:VIMPrivacy_Public] && ![privacy isEqualToString:VIMPrivacy_VOD];
}

- (BOOL)isAvailable
{
    return self.videoStatus == VIMVideoProcessingStatusAvailable;
}

- (BOOL)isTranscoding
{
    return self.videoStatus == VIMVideoProcessingStatusTranscoding;
}

- (BOOL)isUploading
{
    return self.videoStatus == VIMVideoProcessingStatusUploading;
}

// New

- (void)setIsLiked:(BOOL)isLiked
{
    VIMInteraction *interaction = [self interactionWithName:VIMInteractionNameLike];
    interaction.added = @(isLiked);
    
    [self.interactions setValue:interaction forKey:VIMInteractionNameLike];
}

- (void)setIsWatchLater:(BOOL)isWatchLater
{
    VIMInteraction *interaction = [self interactionWithName:VIMInteractionNameWatchLater];
    interaction.added = @(isWatchLater);
    
    [self.interactions setValue:interaction forKey:VIMInteractionNameWatchLater];
}

- (BOOL)isLiked
{
    VIMInteraction *interaction = [self interactionWithName:VIMInteractionNameLike];
    
    return interaction.added.boolValue;
}

- (BOOL)isWatchLater
{
    VIMInteraction *interaction = [self interactionWithName:VIMInteractionNameWatchLater];

    return interaction.added.boolValue;
}

- (BOOL)isRatedAllAudiences
{
    NSString *contentRating = [self singleContentRatingIfAvailable];
    
    return [contentRating isEqualToString:VIMContentRating_Safe];
}

- (BOOL)isNotYetRated
{
    NSString *contentRating = [self singleContentRatingIfAvailable];
    
    return [contentRating isEqualToString:VIMContentRating_Unrated];
}

- (BOOL)isRatedMature
{
    NSString *contentRating = [self singleContentRatingIfAvailable];
    
    return ![contentRating isEqualToString:VIMContentRating_Unrated] && ![contentRating isEqualToString:VIMContentRating_Safe];
}

- (NSString *)singleContentRatingIfAvailable
{
    NSString *contentRating = nil;
    
    if (self.contentRating)
    {
        if ([self.contentRating isKindOfClass:[NSArray class]])
        {
            if ([self.contentRating count] == 1)
            {
                contentRating = [self.contentRating firstObject];
            }
        }
        else if ([self.contentRating isKindOfClass:[NSString class]])
        {
            contentRating = (NSString *)self.contentRating;
        }
    }
    
    return contentRating;
}

- (NSInteger)likesCount
{
    VIMConnection *likesConnection = [self connectionWithName:VIMConnectionNameLikes];
    
    return likesConnection.total.intValue;
}

- (NSInteger)commentsCount
{
    VIMConnection *commentsConnection = [self connectionWithName:VIMConnectionNameComments];
    
    return (self.canViewComments ? commentsConnection.total.intValue : 0);
}

#pragma mark - File Selection

- (VIMVideoFile *)hlsFileForScreenSize:(CGSize)size
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF.quality == %@", VIMVideoFileQualityHLS];
    
    return [self fileForPredicate:predicate screenSize:size];
}

- (VIMVideoFile *)mp4FileForScreenSize:(CGSize)size
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF.quality != %@", VIMVideoFileQualityHLS];

    return [self fileForPredicate:predicate screenSize:size];
}

- (nullable VIMVideoFile *)fallbackFileForFile:(VIMVideoFile *)file screenSize:(CGSize)size
{
    if (!file)
    {
        return nil;
    }
    
    NSPredicate *predicate = nil;
    
    if ([file.quality isEqualToString:VIMVideoFileQualityHLS])
    {
        // There will only ever be one HSL file so we choose !HLS [AH] 8/31/2015
        predicate = [NSPredicate predicateWithFormat:@"SELF.quality != %@", VIMVideoFileQualityHLS];
    }
    else
    {
        if (!file.width ||
            !file.height ||
            [file.width isEqual:[NSNull null]] ||
            [file.height isEqual:[NSNull null]] ||
            [file.width isEqual:@(0)] ||
            [file.height isEqual:@(0)])
        {
            return nil;
        }
        
        // And we want to exclude the file we're falling back from [AH] 8/31/2015
        predicate = [NSPredicate predicateWithFormat:@"SELF.quality != %@ && SELF.width.integerValue < %i", VIMVideoFileQualityHLS, file.width.integerValue];
    }
    
    return [self fileForPredicate:predicate screenSize:size];
}

- (VIMVideoFile *)fileForPredicate:(NSPredicate *)predicate screenSize:(CGSize)size
{
    if (CGSizeEqualToSize(size, CGSizeZero) || predicate == nil)
    {
        return nil;
    }
    
    NSArray *filteredFiles = [self.files filteredArrayUsingPredicate:predicate];
    
    // Sort largest to smallest
    NSArray *sortedFiles = [filteredFiles sortedArrayUsingComparator:^NSComparisonResult(VIMVideoFile *a, VIMVideoFile *b) {
        
        NSNumber *first = [a width];
        NSNumber *second = [b width];
        
        return [second compare:first];
    
    }];
    
    VIMVideoFile *file = nil;
    
    // TODO: augment this to handle portrait videos [AH]
    NSInteger targetScreenWidth = MAX(size.width, size.height);

    for (VIMVideoFile *currentFile in sortedFiles)
    {
        if ([currentFile isSupportedMimeType] && currentFile.link)
        {
            // We dont yet have a file, grab the largest one (based on sort order above)
            if (file == nil)
            {
                file = currentFile;
                
                continue;
            }
            
            // We dont have the info with which to compare the files
            // TODO: is this a problem? HLS files report width/height of 0,0 [AH] 8/31/2015
            if ((file.width == nil || currentFile.width == nil ||
                 [file.width isEqual:[NSNull null]] || [currentFile.width isEqual:[NSNull null]] ||
                 [file.width isEqual:@(0)] || [currentFile.width isEqual:@(0)]))
            {
                continue;
            }
            
            if (currentFile.width.intValue > targetScreenWidth && currentFile.width.intValue < file.width.intValue)
            {
                file = currentFile;
            }
        }
    }
    
//    NSLog(@"selected (%@, %@) for screensize (%@) out of %lu choices with format %@", file.width, file.height, NSStringFromCGSize(size), (unsigned long)[sortedFiles count], predicate.predicateFormat);

    return file;
}

@end
