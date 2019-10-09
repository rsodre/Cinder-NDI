#include "CinderNDIContext.h"
#import "cinder/app/AppImplCocoaRendererGl.h"
#include <memory>


@implementation CinderNDIContext

- (id)init
{
	self = [super init];
	
	NSOpenGLPixelFormat* fmt = [AppImplCocoaRendererGl defaultPixelFormat:0];
	context_ = [[NSOpenGLContext alloc] initWithFormat:fmt shareContext:nil];
	
	return self;
}

- (void)release;
{
	[context_ release];
	[super release];
}

- (NSOpenGLContext*)context
{
	return context_;
}

- (void)makeCurrentContext;
{
	[context_ makeCurrentContext];
}

@end

