#include "CinderNDIContext.h"
#include "cinder/app/AppNative.h"
#import "cinder/app/AppImplCocoaRendererGl.h"
#include <memory>


@implementation CinderNDIContext

- (id)initShared
{
	self = [super init];
	
	NSOpenGLPixelFormat* fmt = [AppImplCocoaRendererGl defaultPixelFormat:0];
	
	auto sharedRenderer = static_cast<ci::app::RendererGl*>( ci::app::AppNative::get()->getRenderer().get() );

	context_ = [[NSOpenGLContext alloc] initWithFormat:fmt shareContext:sharedRenderer->getNsOpenGlContext()];
	
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

