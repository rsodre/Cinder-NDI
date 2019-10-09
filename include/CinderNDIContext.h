#pragma once

#import <Cocoa/Cocoa.h>
#include "cinder/gl/gl.h"

@interface CinderNDIContext : NSObject
{
	NSOpenGLContext		*context_;
}

- (id)init;
- (void)release;
- (NSOpenGLContext*)context;
- (void)makeCurrentContext;

@end
