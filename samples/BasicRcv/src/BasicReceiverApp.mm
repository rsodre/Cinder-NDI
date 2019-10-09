#include "cinder/app/AppNative.h"
#include "cinder/gl/gl.h"
#include "CinderNDIReceiver.h"
#include "CinderNDIFinder.h"
#include "cinder/audio/Voice.h"
#include "cinder/audio/Context.h"

using namespace ci;
using namespace ci::app;

class BasicReceiverApp : public AppNative {
public:
	void setup() override;
	void update() override;
	void draw() override;
	void shutdown() override;
private:
	void sourceAdded( const NDISource& source );
	void sourceRemoved( const std::string sourceName );
	void audioOut( ci::audio::Buffer* audioOutBuffer, size_t sampleRate );
private:
	CinderNDIFinderPtr mCinderNDIFinder;
	CinderNDIReceiverPtr mCinderNDIReceiver;
	ci::signals::connection mNDISourceAdded;
	ci::signals::connection mNDISourceRemoved;
	ci::audio::VoiceRef	mNDIVoice;
};

void BasicReceiverApp::shutdown()
{
	if( mCinderNDIFinder ) {
		mNDISourceAdded.disconnect();	
		mNDISourceRemoved.disconnect();
	}
}

void BasicReceiverApp::sourceAdded( const NDISource& source )
{
	std::cout << "NDI source added: " << source.p_ndi_name <<std::endl;
	// Create the NDI receiver for this source
	if( ! mCinderNDIReceiver ) {
		CinderNDIReceiver::Description recvDscr;
		recvDscr.source = &source;
		mCinderNDIReceiver = std::make_unique<CinderNDIReceiver>( recvDscr );
	}
	else
		mCinderNDIReceiver->connect( source );
}

void BasicReceiverApp::sourceRemoved( std::string sourceName )
{
	std::cout << "NDI source removed: " << sourceName <<std::endl;
}

void BasicReceiverApp::setup()
{
	mNDIVoice = ci::audio::Voice::create( [ this ] ( ci::audio::Buffer* buffer, size_t sampleRate ) {			
		if( mCinderNDIReceiver ) {
			auto audioBuffer = mCinderNDIReceiver->getAudioBuffer();
			if( audioBuffer && ! audioBuffer->isEmpty() ) {
				buffer->copy( *audioBuffer.get() );
			}
		}
	}, ci::audio::Voice::Options().channels( 2 ));
	mNDIVoice->start();
	// Create the NDI finder
	CinderNDIFinder::Description finderDscr;
	mCinderNDIFinder = std::make_unique<CinderNDIFinder>( finderDscr );
	
	mNDISourceAdded = mCinderNDIFinder->getSignalNDISourceAdded().connect(
		std::bind( &BasicReceiverApp::sourceAdded, this, std::placeholders::_1 )
	);
	mNDISourceRemoved = mCinderNDIFinder->getSignalNDISourceRemoved().connect(
		std::bind( &BasicReceiverApp::sourceRemoved, this, std::placeholders::_1 )
	);
}

void BasicReceiverApp::update()
{
	getWindow()->setTitle( "CinderNDI-Receiver - " + std::to_string( (int) getAverageFps() ) + " FPS" );
}

void BasicReceiverApp::draw()
{
	gl::clear( ColorA::black() );
	auto videoTex = mCinderNDIReceiver != nullptr ? mCinderNDIReceiver->getVideoTexture() : nullptr;
	if( videoTex ) {
		Rectf centeredRect = Rectf( videoTex->getBounds() ).getCenteredFit( getWindowBounds(), true );
		gl::draw( videoTex, centeredRect );
	}
}

// This line tells Cinder to actually create and run the application.
CINDER_APP_BASIC( BasicReceiverApp, app::RendererGl )
