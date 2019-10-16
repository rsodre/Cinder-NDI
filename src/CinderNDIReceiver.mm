#include "CinderNDIReceiver.h"
#define CI_MIN_LOG_LEVEL 2
//#include "cinder/Log.h"
#include "cinder/Surface.h"
//#include "cinder/gl/Sync.h"
#include "cinder/audio/Context.h"
#include "CinderNDIContext.h"
#include "Sync.h"
#include <memory>
#include <sys/time.h>

#define VERBOSE 0

CinderNDIReceiver::CinderNDIReceiver( const Description dscr )
{
	if( ! NDIlib_initialize() ) {
		throw std::runtime_error( "Cannot run NDI on this machine. Probably unsupported CPU." );
	}
	NDIlib_recv_create_v3_t recvDscr;
	recvDscr.source_to_connect_to = dscr.source != nullptr ? *(dscr.source) : NDISource();
	recvDscr.color_format = (NDIlib_recv_color_format_e)dscr.mColorFormat;
	recvDscr.bandwidth = (NDIlib_recv_bandwidth_e)dscr.mBandwidth;
	recvDscr.allow_video_fields = dscr.mAllowVideoFields;
	recvDscr.p_ndi_name = dscr.mName != "" ? dscr.mName.c_str() : nullptr;
	mNDIReceiver = NDIlib_recv_create_v3( &recvDscr );	
	if( ! mNDIReceiver ) {
		throw std::runtime_error( "Cannot create NDI Receiver. NDIlib_recv_create_v3 returned nullptr" );
	}
	
	mContext = [[CinderNDIContext alloc] initShared];
//	auto ctx = ci::gl::Context::create( ci::gl::context() );
	
	mVideoFramesBuffer = std::make_unique<VideoFramesBuffer>( 5 );
	mVideoRecvThread = std::make_unique<std::thread>( std::bind( &CinderNDIReceiver::videoRecvThread, this, mContext ) );
	mAudioRecvThread = std::make_unique<std::thread>( std::bind( &CinderNDIReceiver::audioRecvThread, this ) );
}

CinderNDIReceiver::~CinderNDIReceiver()
{
	std::cout << "~CinderNDIReceiver()..." << std::endl;
	{
		mExitVideoThread = true;
		std::cout << "~CinderNDIReceiver() mVideoFramesBuffer->cancel()" << std::endl;
		mVideoFramesBuffer->cancel();
		std::cout << "~CinderNDIReceiver() mVideoRecvThread->join()" << std::endl;
		mVideoRecvThread->join();
	}
	{
		mExitAudioThread = true;
		std::cout << "~CinderNDIReceiver() mAudioRecvThread->join()" << std::endl;
		mAudioRecvThread->join();
	}

	if( mNDIReceiver ) {
		std::cout << "~CinderNDIReceiver() NDIlib_recv_destroy()" << std::endl;
		NDIlib_recv_destroy( mNDIReceiver );
		mNDIReceiver = nullptr;
	}
	std::cout << "~CinderNDIReceiver() NDIlib_destroy()" << std::endl;
	NDIlib_destroy();
	std::cout << "~CinderNDIReceiver() OK" << std::endl;
}

//void CinderNDIReceiver::videoRecvThread( ci::gl::ContextRef ctx )
void CinderNDIReceiver::videoRecvThread( CinderNDIContext* ctx )
{
	[ctx makeCurrentContext];
	while( ! mExitVideoThread ) {
		receiveVideo();
	}
}

void CinderNDIReceiver::audioRecvThread()
{
	while( ! mExitAudioThread ) {
		receiveAudio();
	}
}

void CinderNDIReceiver::connect( const NDISource& source )
{
	NDIlib_recv_connect( mNDIReceiver, &source );
}

void CinderNDIReceiver::disconnect()
{
	NDIlib_recv_connect( mNDIReceiver, nullptr );
}

ci::gl::TextureRef CinderNDIReceiver::getVideoTexture()
{
	if( mVideoFramesBuffer->isNotEmpty() ) {
		mVideoFramesBuffer->popBack( &mVideoTexture );
	}
	return mVideoTexture;
}

void CinderNDIReceiver::receiveVideo()
{
	NDIlib_video_frame_v2_t videoFrame;
	// NDIlib_recv_capture_v2 should be safe to call at the same time from multiple threads according to the SDK.
	// e.g To capture video and audio at the same time from separate threads for example.
	// Wait max .5 sec for a new frame to arrive.
	switch( NDIlib_recv_capture_v2( mNDIReceiver, &videoFrame, nullptr, nullptr, 500 ) ) {
		case NDIlib_frame_type_video:
		{
#if VERBOSE
			std::cout << "Received video frame with resolution : ( " << videoFrame.xres << ", " << videoFrame.yres << " ) " << std::endl;
#endif
			auto surface = ci::Surface( videoFrame.p_data, videoFrame.xres, videoFrame.yres, videoFrame.line_stride_in_bytes, ci::SurfaceChannelOrder::RGBA );
			ci::gl::Texture::Format fmt;
#ifdef BDVJ
			fmt.setWrapS( GL_REPEAT );
			fmt.setWrapT( GL_REPEAT );
			fmt.setTarget( GL_TEXTURE_RECTANGLE_ARB );		// compatible with MovieGl/Syphon
#endif
			auto tex = std::make_shared<ci::gl::Texture>( surface, fmt );
			auto fence = ci::gl::Sync::create();
			fence->clientWaitSync();
			mVideoFramesBuffer->pushFront( tex );
			NDIlib_recv_free_video_v2( mNDIReceiver, &videoFrame );
			break;
		}
		case NDIlib_frame_type_none:
		default:
		{
#if VERBOSE
			std::cout << "No video data available...." << std::endl;
#endif
			break;
		}
	}
	
	updateFrameRate();
}

void CinderNDIReceiver::receiveAudio()
{
	NDIlib_audio_frame_v2_t audioFrame;
	// NDIlib_recv_capture_v2 should be safe to call at the same time from multiple threads according to the SDK.
	// e.g To capture video and audio at the same time from separate threads for example.
	// Wait max .5 sec for a new frame to arrive.
	switch( NDIlib_recv_capture_v2( mNDIReceiver, nullptr, &audioFrame, nullptr, 50 ) ) { 
		case NDIlib_frame_type_audio:
		{
#if VERBOSE
			std::cout << "Received audio frame with no_samples : " << audioFrame.no_samples << " channels: " << audioFrame.no_channels << " channel stride: " << audioFrame.channel_stride_in_bytes << std::endl;
#endif
			{
				std::lock_guard<std::mutex> lock( mAudioMutex );
				if( ! mCurrentAudioBuffer || mCurrentAudioBuffer->getNumChannels() != audioFrame.no_channels ) {
					auto framesPerBlock = ci::audio::Context::master()->getFramesPerBlock();
					mCurrentAudioBuffer = std::make_shared<ci::audio::Buffer>( framesPerBlock, audioFrame.no_channels );
					for( auto& buffer : mRingBuffers ) {
						buffer.clear();
					}
					mRingBuffers.clear();
					for( size_t ch = 0; ch < audioFrame.no_channels; ch++ ) {
						mRingBuffers.emplace_back( audioFrame.no_samples * audioFrame.no_channels );
					}
				}
			}
			for( size_t ch = 0; ch < audioFrame.no_channels; ch++ ) {
				mRingBuffers[ch].write( audioFrame.p_data + ch * audioFrame.no_samples, audioFrame.no_samples );
			}
			NDIlib_recv_free_audio_v2( mNDIReceiver, &audioFrame );
			break;
		}
		default:
		case NDIlib_frame_type_none:
		{
#if VERBOSE
			std::cout << "No audio data available...." << std::endl;
#endif
			break;
		}
	}
}

ci::audio::BufferRef CinderNDIReceiver::getAudioBuffer()
{
	std::lock_guard<std::mutex> lock( mAudioMutex );
	if( mCurrentAudioBuffer ) {
		for( size_t ch = 0; ch < mCurrentAudioBuffer->getNumChannels(); ch++ ) {
			if( ! mRingBuffers[ch].read( mCurrentAudioBuffer->getChannel( ch ), mCurrentAudioBuffer->getNumFrames() ) ) {
				mCurrentAudioBuffer->zero();
			}
		}
	}
	return mCurrentAudioBuffer;
}

//-------------------------------------------------------
// ROGER
//

void CinderNDIReceiver::updateFrameRate()
{
	currentFrame++;
	fpsCount++;
	
	static unsigned int millisStart = 0;
	
	struct timeval now;
	gettimeofday(&now, NULL);
	unsigned int millisNow = (unsigned int) (now.tv_sec * 1000 + now.tv_usec / 1000);
	unsigned int elapsed = millisNow - millisStart;
	if (elapsed > 1000)
	{
		currentFrameRate = ((float)fpsCount / (float)elapsed) * 1000.0;
		millisStart = millisNow;
		fpsCount = 0;
	}
}

void CinderNDIReceiver::bind(int unit)
{
	if(mVideoTexture)
	{
		// Save old GL_TEXTURE_RECTANGLE_ARB binding or else we can mess GL_TEXTURE_2D used after
		glGetBooleanv( GL_TEXTURE_RECTANGLE_ARB, &mOldTargetBinding );
		
		mVideoTexture->enableAndBind(unit);
	}
}

void CinderNDIReceiver::unbind(int unit)
{
	if (mVideoTexture)
	{
		mVideoTexture->unbind(unit);
		
		if( mOldTargetBinding )
			glEnable( GL_TEXTURE_RECTANGLE_ARB );
		else
			glDisable( GL_TEXTURE_RECTANGLE_ARB );
	}
}
