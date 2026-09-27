//
//  PlayerLibSidplayWrapper.mm
//  SIDPLAY
//
//  Created by Alexander Coers on 14.11.24.
//


#import "PlayerLibSidplayWrapper.h"

#include <vector>
// module headers
#include "AudioCoreDriverNew.h"
#include "SidTune.h"

#include <sidplayfp.h>
#include <residfp.h>
#include <resid.h>
#include "residfp-emu.h"

#include "SidTuneInfo.h"
#include "SidTuneInfoImpl.h"
#include "SidInfo.h"
#include "SidConfig.h"

#ifndef NO_USB_SUPPORT
// SIDBlaster USB support
#include "hardsidsb.h"
#include "usbsid_builder.h"
#endif
// always needed
#import "PlayerUsbWorker.h"
#import "USBDeviceWatcher.h"
#import "SPModPlayer.h"


// bins
#include "bin/c.h"
#include "bin/b.h"
#include "bin/k.h"



@implementation PlayerLibSidplayWrapper
@synthesize sChipModel6581;
@synthesize sChipModel8580;
@synthesize sChipModelUnknown;
@synthesize sChipModelUnspecified;


unsigned char sid_registers[ 0x19 ];

static double mixer_value[3] = { 1.0, 1.0, 1.0 };
static double mixer_preMute[3] = { 1.0, 1.0, 1.0 };
static BOOL mixer_muted[3] = { NO, NO, NO };

typedef std::vector<SidRegisterFrame> SidRegisterLog;

// C++ variables
sidplayfp*   mSidEmuEngine;
std::unique_ptr<SidTune>     mSidTune;
std::unique_ptr<ReSIDfpBuilder> mBuilder;
std::unique_ptr<ReSIDBuilder> mBuilder_reSID;
// SIDblaster USB
#ifndef NO_USB_SUPORT
class HardSIDSBBuilder;
class USBSIDBuilder;

HardSIDSBBuilder*   mSIDBlasterUSBbuilder;
USBSIDBuilder*  mUSBSIDPicoBuilder;

#endif



//sid_filter_t        mFilterSettings;
PlaybackSettings    mPlaybackSettings;

SidRegisterLog        mRegisterLog;
struct SidRegisterFrame currentRegisterFrame;


SidTuneInfo*        mTuneInfo;
AudioCoreDriverNew*        mAudioDriver;

static SPModPlayer* mModPlayer = nil;
static BOOL mIsModActive = NO;

- (id)init
{
    self = [super init];
    if (mModPlayer == nil) {
        mModPlayer = [[SPModPlayer alloc] init];
    }
    mIsModActive = NO;
    sChipModel6581        = "MOS 6581";
    sChipModel8580        = "MOS 8580";
    sChipModelUnknown     = "Unknown";
    sChipModelUnspecified = "Unspecified";
    
    mSidEmuEngine = nil;
    mSidTune = nil;
    mTuneInfo = nil;
    mAudioDriver = nil;
    mTuneLength = 0;
    mCurrentSubtune = 0;
    mSubtuneCount = 0;
    mDefaultSubtune = 0;
    mCurrentTempo = 50;
    mPreviousOversamplingFactor = 0;
    mOversamplingBuffer = nil;
#ifndef NO_USB_SUPPORT
    mSIDBlasterUSBbuilder = nil;
    mUSBSIDPicoBuilder  = nil;

    _usbWorker = [[PlayerUsbWorker alloc] init];

    __weak id weakSelf = self;

    self.usbWorker.iterationBlock = ^{
        [weakSelf fillBufferUSB];
    };
    
    self.usbWatcher = [[USBDeviceWatcher alloc] initWithDevices:@[
        @{ @"vid": @(USBSIB_PICO_VENDOR_ID), @"pid": @(USBSIB_PICO_PRODUCT_ID) },
        @{ @"vid": @(0x1234), @"pid": @(0x0002) }
    ] handler:^(USBDeviceEvent event, uint16_t vid, uint16_t pid) {

        __strong id strSelf = weakSelf;
        if (!strSelf) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            switch (event) {
                case USBDeviceEventAttached:
                    [strSelf reconnectVendorId:vid productId:pid];
                    break;

                case USBDeviceEventDetached:
                    [strSelf disconnectVendorId:vid productId:pid];
                    break;
            }
        });
    }];
#endif
    mBuilder_reSID = nil;
    mBuilder = nil;
    mExtUSBDeviceActive = false;
    
    return self;
}
- (void) dealloc
{
#ifndef NO_USB_SUPPORT
    // kill USB so that libusb gets freed
    if (mSIDBlasterUSBbuilder) {
        delete mSIDBlasterUSBbuilder;
        mSIDBlasterUSBbuilder = nil;
    }
    if (mUSBSIDPicoBuilder) {
        delete mUSBSIDPicoBuilder;
        mUSBSIDPicoBuilder  = nil;
    }
#endif
    // empty at the moment...
}

- (void) setupSIDInfo
{
    if (mSidTune == NULL)
        return;
    
    mTuneInfo = (SidTuneInfo *)mSidTune->getInfo();
    mCurrentSubtune = mTuneInfo->currentSong();
    mSubtuneCount = mTuneInfo->songs();
    mDefaultSubtune = mTuneInfo->startSong();
    
    
    //FIXME: FILTER SETTINGS not needed?
    /*
     if (getCurrentChipModel() == sChipModel8580)
     {
     mBuilder->filter((sid_filter_t*)NULL);
     }
     else
     {
     //mFilterSettings.distortion_enable = true;
     mBuilder->filter(&mFilterSettings);
     }
     */
}
- (bool) initSIDTune:(struct PlaybackSettings*) settings
{
    //printf("init sidtune\n");
    /*
    if (mSidTune != NULL)
    {
        delete mSidTune;
        mSidTune = NULL;
        mSidEmuEngine->load(NULL);
    }
    */
    //printf("init emu engine\n");
    
    [self initEmuEngineWithSettings:settings];
    
    mSidTune = std::unique_ptr <SidTune>(new SidTune((uint_least8_t *) mTuneBuffer, mTuneLength));
    
    if (!mSidTune)
        return false;
    
    //printf("created sidtune instance: 0x%08x\n", (int) mSidTune);
    
    mSidTune->selectSong(mCurrentSubtune);
    
    //printf("loading sid tune data\n");
    
    int rc = mSidEmuEngine->load(mSidTune.get());
    
    if (rc == -1)
    {
        //delete mSidTune;
        mSidTune = NULL;
        return false;
    }
#ifndef NO_USB_SUPPORT
    //printf("setting sid tune info\n");
    if (mSIDBlasterUSBbuilder) {
        libsidplayfp::SidTuneInfoImpl *mSidInfo = (libsidplayfp::SidTuneInfoImpl *)mSidTune->getInfo();
        switch (mSidInfo->getClockSpeed())
        {
            case SidTuneInfo::CLOCK_NTSC:
                mSIDBlasterUSBbuilder->setClockToPAL(false);
                break;
            case SidTuneInfo::CLOCK_UNKNOWN:
            case SidTuneInfo::CLOCK_ANY:
            case SidTuneInfo::CLOCK_PAL:
                mSIDBlasterUSBbuilder->setClockToPAL(true);
                break;
        }
    }
    if (mUSBSIDPicoBuilder) {
        libsidplayfp::SidTuneInfoImpl *mSidInfo = (libsidplayfp::SidTuneInfoImpl *)mSidTune->getInfo();
        switch (mSidInfo->getClockSpeed())
        {
            case SidTuneInfo::CLOCK_NTSC:
                mUSBSIDPicoBuilder->setClockToPAL(false);
                break;
            case SidTuneInfo::CLOCK_UNKNOWN:
            case SidTuneInfo::CLOCK_ANY:
            case SidTuneInfo::CLOCK_PAL:
                mUSBSIDPicoBuilder->setClockToPAL(true);
                break;
        }
    }
    
#endif
    [self setupSIDInfo];
    
    return true;
}
//FIXME: For what was this one used?
/*
static inline float approximate_dac(int x, float kinkiness)
{
    float bits = 0.0f;
    for (int i = 0; i < 11; i += 1)
        if (x & (1 << i))
            bits += pow(i, 4) / pow(10, 4);
    
    return x * (1.0f + bits * kinkiness);
    
}
 */
#pragma mark public ObjC methods
- (void) stopEmuEngine
{
    // actually, this does nothing...
}
- (void) setAudioDriver:(void*) audioDriver
{
    mAudioDriver = (AudioCoreDriverNew *)audioDriver;
}
- (void) updateSampleRate:(unsigned int) newSampleRate
{
    if (mSidEmuEngine == NULL)
        return;
    
    mPlaybackSettings.mFrequency = newSampleRate;
    
    SidConfig cfg = mSidEmuEngine->config();
    cfg.frequency      = mPlaybackSettings.mFrequency * mPlaybackSettings.mOversampling;
    
    //mBuilder->sampling(cfg.frequency);
    
    mSidEmuEngine->config(cfg);
}

- (void)initEmuEngineWithSettings:(nonnull struct PlaybackSettings *)settings {
    //reSID VICE params
    double bias = 0;
    
    if (mSidEmuEngine == NULL )
        mSidEmuEngine = new sidplayfp;
    
    // Set up a SID builder
    if (mBuilder == NULL)
        mBuilder = std::unique_ptr<ReSIDfpBuilder> (new ReSIDfpBuilder("reSIDfp"));
    
    if (mBuilder_reSID == NULL)
        mBuilder_reSID = std::unique_ptr<ReSIDBuilder>(new ReSIDBuilder("reSID"));
    
    // set bins
    mSidEmuEngine->setRoms(kernalr, basicr, charr);
    
    if (mAudioDriver)
        settings->mFrequency = mAudioDriver->getSampleRate();
    
    mPlaybackSettings = *settings;
    
    SidConfig cfg = mSidEmuEngine->config();
    if (mPlaybackSettings.mClockSpeed == 0)
    {
        cfg.defaultC64Model    = SidConfig::c64_model_t::PAL;
    }
    else
    {
        cfg.defaultC64Model    = SidConfig::c64_model_t::NTSC;
    }
    //FIXME: check if this is really needed, default settings are always sane
    /*
     
     cfg.clockForced   = true;
     
     cfg.environment   = sid2_envR;
     cfg.playback      = sid2_mono;
     cfg.precision     = mPlaybackSettings.mBits;
     cfg.forceDualSids = false;
     cfg.emulateStereo = false;
     
     cfg.optimisation = SID2_DEFAULT_OPTIMISATION;
     
     switch (mPlaybackSettings.mOptimization)
     {
     case 0:
     cfg.optimisation  = 0;
     break;
     
     case 1:
     cfg.optimisation  = SID2_DEFAULT_OPTIMISATION;
     break;
     
     case 2:
     cfg.optimisation  = SID2_MAX_OPTIMISATION;
     break;
     }
     
     if (mCurrentTempo > 70)
     cfg.optimisation  = SID2_MAX_OPTIMISATION;
     
     // * mPlaybackSettings.mOversampling;
     //printf("optimization: %d\n", cfg.optimisation);
     */
    
    if (!mPlaybackSettings.SIDselectorOverrideActive) {
        if (mPlaybackSettings.mSidModel == 0)
            cfg.defaultSidModel    = SidConfig::MOS6581;
        else
            cfg.defaultSidModel    = SidConfig::MOS8580;
        
        if (mPlaybackSettings.mForceSidModel)
        { // force SID and PAL/NTSC if user wants that
            cfg.forceSidModel = true;
            cfg.forceC64Model = true;
        } else {
            cfg.forceSidModel = false;
            cfg.forceC64Model = false;
            
        }
    } else {
        // manual ovveride of settings
        if (mPlaybackSettings.SIDselectorOverrideModel == 0)
            cfg.defaultSidModel      = SidConfig::MOS6581;
        else
            cfg.defaultSidModel      = SidConfig::MOS8580;
        cfg.forceSidModel = true;
    }
    // set reSID VICE specific config values
    if (cfg.forceSidModel)
    {
        if (cfg.defaultSidModel == SidConfig::MOS6581) {
            bias = 500/1000;
        } else {
            bias = 0;
        }
        
    }
    //    cfg.sidEmulation  = mBuilder;
    //    cfg.sidSamples      = true;
    //    cfg.sampleFormat  = SID2_BIG_UNSIGNED;
    //    setFilterSettingsFromPlaybackSettings(mFilterSettings, settings);
    
    // Get the number of SIDs supported by the engine
    unsigned int maxsids = (mSidEmuEngine->info()) .maxsids();
    
    // Create SID emulators
    mBuilder->create(maxsids);
    mBuilder_reSID->create(maxsids);
#ifndef NO_USB_SUPPORT
    // Set up a SIDblasterUSB builder
    /*
    if (mSIDBlasterUSBbuilder != NULL) {
        delete mSIDBlasterUSBbuilder;
        mSIDBlasterUSBbuilder = NULL;
    }
     */
    if (mSIDBlasterUSBbuilder == NULL) {
        mSIDBlasterUSBbuilder = new HardSIDSBBuilder("SIDBlaster");
        mSIDBlasterUSBbuilder->create(maxsids);
        
        int count  = mSIDBlasterUSBbuilder->availDevices();
        // Check if builder is ok
        if ((!mSIDBlasterUSBbuilder->getStatus()) || (count == 0))
        {
            printf("SIDBlasterUSB configure error: %s\n", mSIDBlasterUSBbuilder->error());
            delete mSIDBlasterUSBbuilder;
            mSIDBlasterUSBbuilder = NULL;
        } else {
            mExtUSBDeviceActive = true;
        }
    }
    /*
    if (mUSBSIDPicoBuilder != NULL) {
        delete mUSBSIDPicoBuilder;
        mUSBSIDPicoBuilder = NULL;
    }
    */
    if (mUSBSIDPicoBuilder == NULL) {
        mUSBSIDPicoBuilder = new USBSIDBuilder("USBSID-Pico");
        mUSBSIDPicoBuilder->create(maxsids);
        
        int count  = mUSBSIDPicoBuilder->availDevices();
        // Check if builder is ok
        if ((!mUSBSIDPicoBuilder->getStatus()) || (count == 0))
        {
            printf("USBSID-Pico configure error: %s\n", mUSBSIDPicoBuilder->error());
            delete mUSBSIDPicoBuilder;
            mUSBSIDPicoBuilder = NULL;
        } else {
            mExtUSBDeviceActive = true;
        }
        if (!mUSBSIDPicoBuilder && !mSIDBlasterUSBbuilder)
            mExtUSBDeviceActive = false;
    }
    
#endif
    
    // Check if builder is ok
    if (!mBuilder->getStatus())
    {
        printf("configure error reSIDfp: %s\n", mBuilder->error());
        return;
    }
    // Check if builder is ok
    if (!mBuilder_reSID->getStatus())
    {
        printf("configure error reSID: %s\n", mBuilder_reSID->error());
        return;
    }
    
    mBuilder_reSID->filter(true);
    mBuilder_reSID->bias(bias);
    
    mBuilder->filter(true);
    mBuilder->filter6581Range(0.5f);
    mBuilder->filter6581Curve(0.3f);
    mBuilder->filter8580Curve(0.3f);
    //    mBuilder->filter(&mFilterSettings);
    //    mBuilder->sampling(cfg.frequency);
    // always configure a builder

    if (mExtUSBDeviceActive) {
        if (mSIDBlasterUSBbuilder)
            cfg.sidEmulation   = (sidbuilder*)mSIDBlasterUSBbuilder;
        if (mUSBSIDPicoBuilder)
            cfg.sidEmulation   = (sidbuilder*)mUSBSIDPicoBuilder;
    } else
        cfg.sidEmulation   = mBuilder.get();  // default residfp
        
    
    cfg.frequency      = mPlaybackSettings.mFrequency;
    cfg.samplingMethod = SidConfig::RESAMPLE_INTERPOLATE;
    cfg.fastSampling   = false;
    cfg.playback       = SidConfig::MONO;
    
    bool rc = mSidEmuEngine->config(cfg);
    if (!rc)
        printf("configure error: %s\n", mSidEmuEngine->error());
    
    //    mSidEmuEngine->setRegisterFrameChangedCallback(NULL, NULL);
    
}

- (BOOL)isTuneLoaded {
    if (mIsModActive && mModPlayer)
        return YES;
    if (mSidTune != nil)
        return YES;
    else
        return NO;
}

- (BOOL) playTuneByPath:(const char *)filename subtune:(int) subtune withSettings:(struct PlaybackSettings *)settings
{
    //printf("loading file: %s\n", filename);
    [self stopPlayback];
    
    bool success = [self loadTuneByPath: filename subtune:subtune withSettings:settings];
    
    //printf("load returned: %d\n", success);
    
    if (success) {
#ifndef NO_USB_SUPPORT
        
        if (mSIDBlasterUSBbuilder) {
            mSIDBlasterUSBbuilder->reset(0x0f);
        }
        if (mUSBSIDPicoBuilder) {
            mUSBSIDPicoBuilder->reset(0x0f);
        }
#endif
        [self startPlayback];
    }
    return success;
}
- (BOOL) playTuneFromBuffer:(char *)buffer withLength:(int) length subtune:(int) subtune withSettings:(struct PlaybackSettings *)settings

{
    //printf( "buffer: 0x%08x, len: %d, subtune: %d\n", (int) buffer, length, subtune );
    //printf( "buffer: %c %c %c %c\n", buffer[0], buffer[1], buffer[2], buffer[3] );
    [self stopPlayback];
    
    bool success = [self loadTuneFromBuffer: buffer withLength: length subtune:subtune withSettings:settings];
    
    if (success) {
#ifndef NO_USB_SUPPORT
        if (mSIDBlasterUSBbuilder) {
            mSIDBlasterUSBbuilder->reset(0x0f);
        }
        if (mUSBSIDPicoBuilder) {
            mUSBSIDPicoBuilder->reset(0x0f);
        }
#endif
        [self startPlayback];
    }
    return success;
}
- (BOOL) loadTuneByPath:(const char *)filename subtune:(int) subtune withSettings:(struct PlaybackSettings *)settings
{
    NSString* pathStr = [NSString stringWithUTF8String:filename];
    if (mModPlayer && [SPModPlayer isModFile:pathStr])
    {
        int sampleRate = mAudioDriver ? mAudioDriver->getSampleRate() : 48000;
        if ([mModPlayer loadTuneByPath:pathStr sampleRate:sampleRate])
        {
            mIsModActive = YES;
            mSidTune = nullptr;
            mCurrentSubtune = [mModPlayer getCurrentSubtune];
            mSubtuneCount = [mModPlayer getSubtuneCount];
            mDefaultSubtune = 1;
            mTuneLength = 0;
            return YES;
        }
    }

    mIsModActive = NO;
    if (mModPlayer)
        [mModPlayer stopPlayback];

    FILE* fp = fopen(filename, "rb");
    
    if ( fp == NULL )
        return false;
    
    long length = fread(mTuneBuffer, 1,TUNE_BUFFER_SIZE, fp);
    
    if (length < 0)
        return false;
    
    //printf("file reading worked\n");
    
    fclose(fp);
    
    mTuneLength = (int)length;
    mCurrentSubtune = subtune;
    
    return [self initSIDTune:settings];
}
- (BOOL) loadTuneFromBuffer:(char *)buffer withLength:(int) length subtune:(int) subtune withSettings:(struct PlaybackSettings *)settings
{
    if (length <= 0)
        return false;

    NSData* data = [NSData dataWithBytesNoCopy:buffer length:length freeWhenDone:NO];
    if (mModPlayer && [SPModPlayer isModData:data])
    {
        int sampleRate = mAudioDriver ? mAudioDriver->getSampleRate() : 48000;
        if ([mModPlayer loadTuneFromBuffer:buffer withLength:length sampleRate:sampleRate])
        {
            mIsModActive = YES;
            mSidTune = nullptr;
            mCurrentSubtune = [mModPlayer getCurrentSubtune];
            mSubtuneCount = [mModPlayer getSubtuneCount];
            mDefaultSubtune = 1;
            mTuneLength = length;
            return YES;
        }
    }

    mIsModActive = NO;
    if (mModPlayer)
        [mModPlayer stopPlayback];

    if (length > TUNE_BUFFER_SIZE)
        return false;
    
    if (buffer[0] != 'P' && buffer[0] != 'R')
        return false;
    
    if ( buffer[1] != 'S' ||
        buffer[2] != 'I' ||
        buffer[3] != 'D' )
    {
        return false;
    }
    
    mTuneLength = length;
    memcpy(mTuneBuffer, buffer, length);
    mCurrentSubtune = subtune;
    
    return [self initSIDTune:settings];
}

- (BOOL) startPrevSubtune
{
    if (mCurrentSubtune > 1)
        mCurrentSubtune--;
    else
        return true;
    [self stopPlayback];
    [self initCurrentSubtune];
    [self startPlayback];
    return true;
}

- (BOOL) startNextSubtune
{
    if (mCurrentSubtune < mSubtuneCount)
        mCurrentSubtune++;
    else
        return true;
    
    [self stopPlayback];
    
    [self initCurrentSubtune];
    
    [self startPlayback];
    
    return true;
}

- (BOOL) startSubtune:(int) which
{
    if (which >= 1 && which <= mSubtuneCount)
        mCurrentSubtune = which;
    else
        return true;
    
    [self stopPlayback];
    
    [self initCurrentSubtune];
    
    [self startPlayback];
    
    return true;
}

- (BOOL) initCurrentSubtune
{
    if (mIsModActive && mModPlayer) {
        return [mModPlayer startSubtune:mCurrentSubtune];
    }
    if (mSidTune == NULL)
        return false;
    
    if (mSidEmuEngine == NULL)
        return false;
    
    mSidTune->selectSong(mCurrentSubtune);
    mSidEmuEngine->load(mSidTune.get());
    
    return true;
}

- (int) getTempo
{
    return mCurrentTempo;
}

- (void) setTempo:(int)tempo
{
    if (mSidEmuEngine == NULL)
        return;
    
    // tempo is from 0..100, default is 50
    // 50 should yield a fastForward parameter of 100 (normal speed)
    // 0 should yield a fastForward parameter of 200 (half speed)
    // 100 should yield a fastForward parameter of 5 (20x speed)
    
    mCurrentTempo = tempo;
    
    tempo = 200 - tempo * 2;
    
    if (tempo < 5)
        tempo = 5;
    /* FIXME: Override Optimization? Available?
     if (tempo < 50)
     mBuilder->overrideOptimisation(SID2_MAX_OPTIMISATION);
     else
     mBuilder->overrideOptimisation(mPlaybackSettings.mOptimization);
     */
    mSidEmuEngine->fastForward( 10000 / tempo );
}

- (void) setVoiceVolume:(float)volume forVoice:(int) voice
{
    if (mIsModActive && mModPlayer) {
        [mModPlayer setVoiceVolume:volume forVoice:voice];
        return;
    }
    if (mSidEmuEngine == NULL)
        return;
    if (mBuilder_reSID == NULL)
        return;
    int numberSids = mBuilder_reSID->usedDevices();
    
    if (voice < 0 || voice > 2)
        return;

    mixer_value[voice] = volume;
    if (!mixer_muted[voice])
        mixer_preMute[voice] = volume;
    if (volume == 0)
        for (int i=0;i<numberSids;i++)
            mSidEmuEngine->mute(i, voice, true);
    else
        for (int i=0;i<numberSids;i++)
            mSidEmuEngine->mute(i, voice, false);
}

- (float) voiceVolumeForVoice:(int) voice
{
    if (mIsModActive && mModPlayer) {
        return [mModPlayer voiceVolumeForVoice:voice];
    }
    if (voice < 0 || voice > 2)
        return 0.0f;
    return (float)mixer_value[voice];
}

- (float) voicePreMuteVolumeForVoice:(int) voice
{
    if (mIsModActive && mModPlayer) {
        return [mModPlayer voicePreMuteVolumeForVoice:voice];
    }
    if (voice < 0 || voice > 2)
        return 0.0f;
    return (float)mixer_preMute[voice];
}

- (BOOL) isVoiceMuted:(int) voice
{
    if (mIsModActive && mModPlayer) {
        return [mModPlayer isVoiceMuted:voice];
    }
    if (voice < 0 || voice > 2)
        return NO;
    return mixer_muted[voice];
}

- (void) setVoiceMuted:(BOOL)muted forVoice:(int) voice
{
    if (mIsModActive && mModPlayer) {
        [mModPlayer setVoiceMuted:muted forVoice:voice];
        return;
    }
    if (mSidEmuEngine == NULL)
        return;
    if (mBuilder_reSID == NULL)
        return;
    if (voice < 0 || voice > 2)
        return;

    if (muted == mixer_muted[voice])
        return;

    mixer_muted[voice] = muted;
    if (muted)
    {
        mixer_preMute[voice] = mixer_value[voice];
        [self setVoiceVolume:0.0f forVoice:voice];
    }
    else
    {
        float restoreVolume = (float)mixer_preMute[voice];
        [self setVoiceVolume:restoreVolume forVoice:voice];
    }
}

- (void) toggleVoiceMuted:(int) voice
{
    if (mIsModActive && mModPlayer) {
        [mModPlayer toggleVoiceMuted:voice];
        return;
    }
    [self setVoiceMuted:![self isVoiceMuted:voice] forVoice:voice];
}
/* FIXME: FILTER SETTINGS?!
 // ----------------------------------------------------------------------------
 void PlayerLibSidplay::setFilterSettings(sid_filter_t* filterSettings)
 // ----------------------------------------------------------------------------
 {
 
 mFilterSettings = *filterSettings;
 if (mBuilder)
 mBuilder->filter(&mFilterSettings);
 
 }
 */

- (int) getPlaybackSeconds
{
    if (mIsModActive && mModPlayer)
        return [mModPlayer getPlaybackSeconds];
    if (mSidEmuEngine == NULL)
        return 0;
    
    return(mSidEmuEngine->time());// / 10);
}

- (int) getTotalTime
{
    if (mIsModActive && mModPlayer)
        return [mModPlayer getTotalTimeSeconds];
    return 0;
}

- (void) fillBufferUSB
{
    // USB devices do not fill buffer, but need to be triggerd
    short buffer[20]; // 20 Bytes safety...
    if (mExtUSBDeviceActive) {
        for (int i = 0;i<50;i++)
            if (self.isPlaying)
                mSidEmuEngine->play(buffer, 0);
        
        return;
    }
}
- (void) startPlayback
{
    if (mIsModActive && mModPlayer) {
        [mModPlayer startPlayback];
        mAudioDriver->startPlayback();
        return;
    }
#ifndef NO_USB_SUPPORT
    if (mExtUSBDeviceActive)
        [self.usbWorker start];
#endif
        mAudioDriver->startPlayback();
}
- (void) pausePlayback
{
    if (mIsModActive && mModPlayer) {
        [mModPlayer pausePlayback];
        mAudioDriver->stopPlayback();
        return;
    }
#ifndef NO_USB_SUPPORT
    if (mExtUSBDeviceActive)
        [self.usbWorker pause];
#endif
        mAudioDriver->stopPlayback();
}
- (void) resumePlayback
{
    if (mIsModActive && mModPlayer) {
        [mModPlayer resumePlayback];
        mAudioDriver->startPlayback();
        return;
    }
#ifndef NO_USB_SUPPORT
    if (mExtUSBDeviceActive)
        [self.usbWorker resume];
#endif
        mAudioDriver->startPlayback();
}
- (void) stopPlayback
{
    if (mIsModActive && mModPlayer) {
        [mModPlayer stopPlayback];
        mAudioDriver->stopPlayback();
        return;
    }
#ifndef NO_USB_SUPPORT
    if (mExtUSBDeviceActive)
        [self.usbWorker stop];
#endif
        mAudioDriver->stopPlayback();
}
- (BOOL) isPlaying
{
    if (mIsModActive && mModPlayer)
        return [mModPlayer isPlaying];
#ifndef NO_USB_SUPPORT
    if (mExtUSBDeviceActive)
        return self.usbWorker.isPlaying;
#endif
        return mAudioDriver->getIsPlaying();
}
- (BOOL) usbError
{
    return mUsbErrorDetectedPico | mUsbErrorDetectedSB;
}
- (void)reconnectVendorId:(uint16_t)vid productId:(uint16_t)pid
{
    NSLog(@"USB Device pid=0x%x, vid=0x%x connected", pid, vid);
    // at the moment we do not support auto config
}
- (void)disconnectVendorId:(uint16_t)vid productId:(uint16_t)pid
{
    NSLog(@"USB Device pid=0x%x, vid=0x%x disconnected", pid, vid);
    if ((pid == USBSIB_PICO_PRODUCT_ID) && (vid == USBSIB_PICO_VENDOR_ID)) {
        // USBSID-Pico lost
        if (mUSBSIDPicoBuilder) {
            self->mUsbErrorDetectedPico = TRUE;
            [self.usbWorker stop];
            mSidEmuEngine->stop();
        }
    }
}
- (void)releaseUSBDevices
{
    // we try to remove libusb devices
    if (mUSBSIDPicoBuilder) {
        delete mUSBSIDPicoBuilder;
        mUSBSIDPicoBuilder = nil;
    }
    if (mSIDBlasterUSBbuilder) {
        delete mSIDBlasterUSBbuilder;
        mSIDBlasterUSBbuilder = nil;
    }
}

//FIXME: we have void* defined, but use now short*
- (void) fillBuffer:(void*) buffer withLen: (int) len
{
    if (mIsModActive && mModPlayer) {
        [mModPlayer fillBuffer:buffer withLen:len];
        return;
    }
    if (mSidEmuEngine == NULL)
        return;
    //libsidplayfp uses number of 16-Bit samples (short), not bytes for buffer count
    int count16 = len/2;
    
    if (mPlaybackSettings.mOversampling == 1) {
        if (!mExtUSBDeviceActive)
            mSidEmuEngine->play((short *)buffer, count16);
    }else
    {
        if (mPlaybackSettings.mOversampling != mPreviousOversamplingFactor)
        {
            delete[] mOversamplingBuffer;
            mOversamplingBuffer = new char[len * mPlaybackSettings.mOversampling];
            mPreviousOversamplingFactor = mPlaybackSettings.mOversampling;
        }
        
        // calculate n times as much sample data
        if (!mExtUSBDeviceActive)
            mSidEmuEngine->play((short *)mOversamplingBuffer, (count16 * mPlaybackSettings.mOversampling)/2);
        
        short *oversampleBuffer = (short*) mOversamplingBuffer;
        short *outputBuffer = (short*) buffer;
        long sample = 0;
        
        // downsample n:1 where n = oversampling factor
        for (int sampleCount = len / sizeof(short); sampleCount > 0; sampleCount--)
        {
            // calc arithmetic average (should rather be median?)
            sample = 0;
            
            for (int i = 0; i < mPlaybackSettings.mOversampling; i++ )
            {
                sample += *oversampleBuffer++;
            }
            
            *outputBuffer++ = (short) (sample / mPlaybackSettings.mOversampling);
        }
    }
}

- (const short*) voiceScopeBufferForVoice:(int) voice
{
    if (mIsModActive && mModPlayer) {
        return [mModPlayer voiceScopeBufferForVoice:voice];
    }
    if (voice < 0 || voice > 2)
        return NULL;
    if (mBuilder == NULL)
        return NULL;
    libsidplayfp::ReSIDfp* sid = mBuilder->getSid(0);
    if (sid == nullptr)
        return NULL;
    return sid->scopeBuffer((unsigned int)voice);
}

- (unsigned int) voiceScopeBufferSize
{
    if (mIsModActive && mModPlayer) {
        return [mModPlayer voiceScopeBufferSize];
    }
    if (mBuilder == NULL)
        return 0;
    libsidplayfp::ReSIDfp* sid = mBuilder->getSid(0);
    if (sid == nullptr)
        return 0;
    return sid->scopeBufferSize();
}

- (unsigned int) voiceScopeWriteIndex
{
    if (mIsModActive && mModPlayer) {
        return [mModPlayer voiceScopeWriteIndex];
    }
    if (mBuilder == NULL)
        return 0;
    libsidplayfp::ReSIDfp* sid = mBuilder->getSid(0);
    if (sid == nullptr)
        return 0;
    return sid->scopeBufferWriteIndex();
}
- (int) hasTuneInformationStrings
{
    if (mIsModActive && mModPlayer)
        return 1;
    return mTuneInfo ? (mTuneInfo->numberOfInfoStrings() >= 3) : 0;
}

- (const char*) getCurrentTitle
{
    if (mIsModActive && mModPlayer) {
        return [mModPlayer getCurrentTitle];
    }
    return mTuneInfo ? mTuneInfo->infoString(0) : "";
}

- (const char*) getCurrentAuthor
{
    if (mIsModActive && mModPlayer) {
        return [mModPlayer getCurrentAuthor];
    }
    return mTuneInfo ? mTuneInfo->infoString(1) : "";
}
- (const char*) getCurrentReleaseInfo
{
    if (mIsModActive && mModPlayer) {
        return [mModPlayer getCurrentReleaseInfo];
    }
    return mTuneInfo ? mTuneInfo->infoString(2) : "";
}
- (unsigned short) getCurrentLoadAddress
{
    if (mIsModActive)
        return 0;
    return mTuneInfo ? mTuneInfo->loadAddr() : 0;
}
- (unsigned short) getSidChips
{
    if (mIsModActive)
        return 0;
    return mTuneInfo ? mTuneInfo->sidChips() : 0;
}
- (unsigned short) getCurrentInitAddress
{
    if (mIsModActive)
        return 0;
    return mTuneInfo ? mTuneInfo->initAddr() : 0;
}
- (unsigned short) getCurrentPlayAddress
{
    if (mIsModActive)
        return 0;
    return mTuneInfo ? mTuneInfo->playAddr() : 0;
}
- (const char*) getCurrentFormat
{
    if (mIsModActive && mModPlayer) {
        return [mModPlayer getCurrentFormat];
    }
    return mTuneInfo ? mTuneInfo->formatString() : "";
}
- (int) getCurrentFileSize;
{
    if (mIsModActive)
        return mTuneLength;
    return mTuneInfo ? mTuneInfo->dataFileLen() : 0;
}
- (const char*) getCurrentChipModel
{
    if (mIsModActive && mModPlayer) {
        return "Amiga Paula (4-voice 8-bit D/A)";
    }
    if (mTuneInfo != NULL) {
        if (mTuneInfo->sidModel(0) == SidTuneInfo::SIDMODEL_6581)
            return sChipModel6581;
        
        if (mTuneInfo->sidModel(0) == SidTuneInfo::SIDMODEL_8580)
            return sChipModel8580;
    }
    return sChipModelUnspecified;
}
- (struct PlaybackSettings*) getCurrentPlaybackSettings
{
    return &mPlaybackSettings;
}
- (int) getCurrentSubtune
{
    if (mIsModActive && mModPlayer)
        return [mModPlayer getCurrentSubtune];
    return mCurrentSubtune;
}
- (int) getSubtuneCount
{
    if (mIsModActive && mModPlayer)
        return [mModPlayer getSubtuneCount];
    return mSubtuneCount;
}
- (int) getDefaultSubtune
{
    return mDefaultSubtune;
}
// for popoverSIDSelector
- (int) getSIDModelFromTune
{
    if (mIsModActive)
        return M_UNKNOWN;
    if (mTuneInfo != NULL) {
        if (mTuneInfo->sidModel(0) == SidTuneInfo::SIDMODEL_6581)
            return M_6581;
        if (mTuneInfo->sidModel(0) == SidTuneInfo::SIDMODEL_8580)
            return M_8580;
    }
    return M_UNKNOWN;
}
- (BOOL) isUsbDeviceActive
{
    return mExtUSBDeviceActive;
}
- (BOOL) isCurrentTuneMod
{
    return mIsModActive;
}
- (char*) getTuneBuffer:(int *)outTuneLength
{
    *outTuneLength = mTuneLength;
    return mTuneBuffer;
}

/* FIXME: Again filter settings....
 // ----------------------------------------------------------------------------
 void PlayerLibSidplay::setFilterSettingsFromPlaybackSettings(sid_filter_t& filterSettings, PlaybackSettings* settings)
 // ----------------------------------------------------------------------------
 {
 filterSettings.distortion_enable = settings->mEnableFilterDistortion;
 filterSettings.rate = settings->mDistortionRate;
 filterSettings.headroom = settings->mDistortionHeadroom;
 
 if (settings->mFilterType == SID_FILTER_8580)
 {
 filterSettings.opmin = -99999;
 filterSettings.opmax = 99999;
 filterSettings.distortion_enable = false;
 
 filterSettings.points = sDefault8580PointCount;
 memcpy(filterSettings.cutoff, sDefault8580, sizeof(sDefault8580));
 }
 else
 {
 filterSettings.opmin = -20000;
 filterSettings.opmax = 20000;
 
 filterSettings.points = 0x800;
 
 for (int i = 0; i < 0x800; i++)
 {
 float i_kinked = approximate_dac(i, settings->mFilterKinkiness);
 float freq = settings->mFilterBaseLevel + powf(2.0f, (i_kinked - settings->mFilterOffset) / settings->mFilterSteepness);
 
 // Better expression for this required.
 // As it stands, it's kinda embarrassing.
 for (float j = 1000.f; j < 18500.f; j += 500.f)
 {
 if (freq > j)
 freq -= (freq - j) / settings->mFilterRolloff;
 }
 if (freq > 18500)
 freq = 18500;
 
 filterSettings.cutoff[i][0] = i;
 filterSettings.cutoff[i][1] = freq;
 }
 }
 
 }
 */

#pragma mark SID register methods
- (struct SidRegisterFrame*) getCurrentSidRegisters
{
    if (mSidEmuEngine != NULL) {
        mSidEmuEngine->getSidStatus(0, &currentRegisterFrame.mRegisters[0]);
        return &currentRegisterFrame;
    }
    else
        return &currentRegisterFrame;
}

- (void) sidRegisterFrameHasChanged:(void*) inInstance inFrame:(SidRegisterFrame *) inRegisterFrame

{
    /*
     printf("Frame %d: ", inRegisterFrame.mTimeStamp);
     
     for (int i = 0; i < SIDPLAY2_NAMESPACE::SidRegisterFrame::SID_REGISTER_COUNT; i++)
     printf("%02x ", inRegisterFrame.mRegisters[i]);
     
     printf("\n");
     */
    //FIXME: Fix vector things
    //PlayerLibSidplay* player = (PlayerLibSidplay*) inInstance;
    //if (player != NULL)
    //  player->mRegisterLog.push_back(inRegisterFrame);
}


@end
