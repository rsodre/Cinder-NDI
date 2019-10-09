#include "cinder/app/AppNative.h"
#include "cinder/gl/gl.h"

using namespace ci;
using namespace ci::app;
using namespace std;

class BasicRcvApp : public AppNative {
  public:
	void setup();
	void mouseDown( MouseEvent event );	
	void update();
	void draw();
};

void BasicRcvApp::setup()
{
}

void BasicRcvApp::mouseDown( MouseEvent event )
{
}

void BasicRcvApp::update()
{
}

void BasicRcvApp::draw()
{
	// clear out the window with black
	gl::clear( Color( 0, 0, 0 ) ); 
}

CINDER_APP_NATIVE( BasicRcvApp, RendererGl )
