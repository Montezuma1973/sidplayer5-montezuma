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
#import "SPSidNoteUtils.h"


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

static double mixer_value[6] = { 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 };
static double mixer_preMute[6] = { 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 };
static BOOL mixer_muted[6] = { NO, NO, NO, NO, NO, NO };
static BOOL mixer_soloed[6] = { NO, NO, NO, NO, NO, NO };
static float mixer_vuPeak[6] = { 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f };

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
struct SidRegisterFrame currentRegisterFrame2;

struct SPC64TrackerCell {
    char note[8];
    char ins[4];
    char vol[4];
    char fx[6];
};

static SPC64TrackerCell sC64PatternMatrix[64][64][6];
static int sC64LastRecordedPattern = -1;
static int sC64LastRecordedRow = -1;

SidTuneInfo*        mTuneInfo;
AudioCoreDriverNew*        mAudioDriver;

static SPModPlayer* mModPlayer = nil;
static BOOL mIsModActive = NO;

- (id)init
{
    self = [super init];
    [self resetC64TrackerState];
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
    [self resetC64TrackerState];
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
    cfg.playback       = (mPlaybackSettings.mStereo || (mTuneInfo && mTuneInfo->sidChips() > 1)) ? SidConfig::STEREO : SidConfig::MONO;
    
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
            mSubtuneCount = [mModPlayer getSubtuneCount];
            if (subtune > 0 && subtune <= mSubtuneCount) {
                [mModPlayer startSubtune:subtune];
            }
            mCurrentSubtune = [mModPlayer getCurrentSubtune];
            mDefaultSubtune = 1;
            mTuneLength = [mModPlayer getTotalTimeSeconds];
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
            mSubtuneCount = [mModPlayer getSubtuneCount];
            if (subtune > 0 && subtune <= mSubtuneCount) {
                [mModPlayer startSubtune:subtune];
            }
            mCurrentSubtune = [mModPlayer getCurrentSubtune];
            mDefaultSubtune = 1;
            mTuneLength = [mModPlayer getTotalTimeSeconds];
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
    [self resetC64TrackerState];
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
    int numberSids = mBuilder_reSID ? mBuilder_reSID->usedDevices() : 1;
    int maxVoices = numberSids * 3;
    if (voice < 0 || voice >= maxVoices || voice >= 6)
        return;

    mixer_value[voice] = volume;
    if (!mixer_muted[voice])
        mixer_preMute[voice] = volume;

    int chip = (voice < 3) ? 0 : 1;
    int chipVoice = voice % 3;
    if (mSidEmuEngine) {
        mSidEmuEngine->mute(chip, chipVoice, (volume == 0));
    }
}

- (float) voiceVolumeForVoice:(int) voice
{
    if (mIsModActive && mModPlayer) {
        return [mModPlayer voiceVolumeForVoice:voice];
    }
    if (voice < 0 || voice >= 6)
        return 0.0f;
    return (float)mixer_value[voice];
}

- (float) voicePreMuteVolumeForVoice:(int) voice
{
    if (mIsModActive && mModPlayer) {
        return [mModPlayer voicePreMuteVolumeForVoice:voice];
    }
    if (voice < 0 || voice >= 6)
        return 0.0f;
    return (float)mixer_preMute[voice];
}

- (BOOL) isVoiceMuted:(int) voice
{
    if (mIsModActive && mModPlayer) {
        return [mModPlayer isVoiceMuted:voice];
    }
    if (voice < 0 || voice >= 6)
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
    int numberSids = mBuilder_reSID->usedDevices();
    int maxVoices = numberSids * 3;
    if (voice < 0 || voice >= maxVoices || voice >= 6)
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

- (int) activeChannelCount
{
    if (mIsModActive && mModPlayer) {
        return [mModPlayer numChannels];
    }
    int sids = 1;
    if (mSidEmuEngine) {
        sids = mSidEmuEngine->installedSIDs();
    } else if (mBuilder_reSID) {
        sids = mBuilder_reSID->usedDevices();
    }
    return (sids > 1) ? 6 : 3;
}

- (BOOL) isVoiceSoloed:(int) voice
{
    if (mIsModActive && mModPlayer) {
        return [mModPlayer isVoiceSoloed:voice];
    }
    if (voice < 0 || voice >= 6) return NO;
    return mixer_soloed[voice];
}

- (void) toggleVoiceSoloed:(int) voice
{
    if (mIsModActive && mModPlayer) {
        [mModPlayer toggleVoiceSoloed:voice];
        return;
    }
    int totalVoices = [self activeChannelCount];
    if (voice < 0 || voice >= totalVoices) return;

    if (mixer_soloed[voice]) {
        for (int i = 0; i < totalVoices; i++) {
            mixer_soloed[i] = NO;
            [self setVoiceMuted:NO forVoice:i];
        }
    } else {
        for (int i = 0; i < totalVoices; i++) {
            mixer_soloed[i] = (i == voice);
            [self setVoiceMuted:(i != voice) forVoice:i];
        }
    }
}

- (void) unmuteAllVoices
{
    if (mIsModActive && mModPlayer) {
        [mModPlayer unmuteAllVoices];
        return;
    }
    int totalVoices = [self activeChannelCount];
    for (int i = 0; i < totalVoices; i++) {
        mixer_soloed[i] = NO;
        [self setVoiceMuted:NO forVoice:i];
    }
}

- (float) voiceVUPeakForVoice:(int) voice
{
    if (mIsModActive && mModPlayer) {
        return [mModPlayer voiceVUPeakForVoice:voice];
    }
    if (voice < 0 || voice >= 6) return 0.0f;
    if (mixer_muted[voice]) return 0.0f;

    const short* buf = [self voiceScopeBufferForVoice:voice];
    if (buf) {
        unsigned int writeIdx = [self voiceScopeWriteIndex];
        unsigned int bufSize = [self voiceScopeBufferSize];
        int maxVal = 0;
        for (int i = 0; i < 64; i++) {
            int idx = (writeIdx + bufSize - 1 - i) % bufSize;
            int val = abs(buf[idx]);
            if (val > maxVal) maxVal = val;
        }
        float raw = (float)maxVal / 32768.0f;
        if (raw > mixer_vuPeak[voice]) {
            mixer_vuPeak[voice] = raw;
        } else {
            mixer_vuPeak[voice] = mixer_vuPeak[voice] * 0.86f;
        }
        return mixer_vuPeak[voice];
    }

    struct SidRegisterFrame* regFrame = [self getCurrentSidRegisters];
    if (regFrame && voice < 3) {
        int regOffset = voice * 7;
        uint8_t control = regFrame->mRegisters[regOffset + 4];
        BOOL gate = (control & 0x01) != 0;
        uint8_t susRel = regFrame->mRegisters[regOffset + 6];
        uint8_t sustain = (susRel >> 4) & 0x0F;
        float level = gate ? (sustain / 15.0f * 0.75f + 0.25f) : 0.0f;
        if (level > mixer_vuPeak[voice]) {
            mixer_vuPeak[voice] = level;
        } else {
            mixer_vuPeak[voice] = mixer_vuPeak[voice] * 0.86f;
        }
        return mixer_vuPeak[voice];
    }
    return 0.0f;
}

- (NSString*) channelNoteForVoice:(int) voice
{
    if (mIsModActive && mModPlayer) {
        return [mModPlayer channelNoteForVoice:voice];
    }
    if (voice < 0 || voice >= 6) return @"--";
    if (voice >= 3 && (!mSidEmuEngine || mSidEmuEngine->installedSIDs() <= 1)) return @"--";
    if (mixer_muted[voice]) return @"--";
    struct SidRegisterFrame* regFrame = (voice >= 3) ? [self getCurrentSidRegisters2] : [self getCurrentSidRegisters];
    if (!regFrame) return @"--";
    int regOffset = (voice % 3) * 7;
    uint16_t freq = regFrame->mRegisters[regOffset] | (regFrame->mRegisters[regOffset + 1] << 8);
    uint8_t control = regFrame->mRegisters[regOffset + 4];
    BOOL gateOn = (control & 0x01) != 0;
    const char* noteStr = gateOn ? SPSidNoteStringForFrequency(freq) : "--";
    if (!noteStr || noteStr[0] == '\0') return @"--";
    return [NSString stringWithUTF8String:noteStr];
}

- (NSString*) channelInstrumentForVoice:(int) voice
{
    if (mIsModActive && mModPlayer) {
        return [mModPlayer channelInstrumentForVoice:voice];
    }
    if (voice < 0 || voice >= 6) return @"--";
    if (voice >= 3 && (!mSidEmuEngine || mSidEmuEngine->installedSIDs() <= 1)) return @"--";
    struct SidRegisterFrame* regFrame = (voice >= 3) ? [self getCurrentSidRegisters2] : [self getCurrentSidRegisters];
    if (!regFrame) return @"--";
    int regOffset = (voice % 3) * 7;
    uint8_t control = regFrame->mRegisters[regOffset + 4];
    BOOL gateOn = (control & 0x01) != 0;
    if (!gateOn) return @"--";
    uint8_t waveform = control & 0xF0;
    NSMutableArray<NSString*>* parts = [NSMutableArray arrayWithCapacity:4];
    if (waveform & 0x10) [parts addObject:@"Tri"];
    if (waveform & 0x20) [parts addObject:@"Saw"];
    if (waveform & 0x40) [parts addObject:@"Pulse"];
    if (waveform & 0x80) [parts addObject:@"Noise"];
    if (parts.count == 0) return @"--";
    return [parts componentsJoinedByString:@"+"];
}

- (int) channelPeriodForVoice:(int) voice
{
    if (mIsModActive && mModPlayer) {
        return [mModPlayer channelPeriodForVoice:voice];
    }
    if (voice < 0 || voice >= 6) return 0;
    if (voice >= 3 && (!mSidEmuEngine || mSidEmuEngine->installedSIDs() <= 1)) return 0;
    struct SidRegisterFrame* regFrame = (voice >= 3) ? [self getCurrentSidRegisters2] : [self getCurrentSidRegisters];
    if (!regFrame) return 0;
    int regOffset = (voice % 3) * 7;
    return regFrame->mRegisters[regOffset] | (regFrame->mRegisters[regOffset + 1] << 8);
}

- (double) c64MsPerRow
{
    double msPerRow = 120.0;
    if (mSidEmuEngine != NULL) {
        uint_least16_t timerA = mSidEmuEngine->getCia1TimerA();
        BOOL isPal = YES;
        if (mTuneInfo != NULL && mTuneInfo->clockSpeed() == SidTuneInfo::CLOCK_NTSC) {
            isPal = NO;
        }
        double cpuClock = isPal ? 985248.0 : 1022727.0;
        
        if (timerA >= 2000 && timerA <= 40000) {
            double timerHz = cpuClock / (double)timerA;
            int speed = 6;
            if (timerHz > 160.0) {
                speed = 12;
            }
            msPerRow = ((double)speed / timerHz) * 1000.0;
            if (msPerRow < 60.0) msPerRow = 60.0;
            if (msPerRow > 250.0) msPerRow = 250.0;
        } else if (!isPal) {
            msPerRow = 100.0;
        }
    }
    return msPerRow;
}

- (int) c64CurrentBPM
{
    double msPerRow = [self c64MsPerRow];
    if (msPerRow <= 0.0) return 125;
    int bpm = (int)round((60000.0 / msPerRow) / 4.0);
    if (bpm < 32) bpm = 32;
    if (bpm > 300) bpm = 300;
    return bpm;
}

- (int) c64CurrentSpeed
{
    return 6;
}

- (int) c64CurrentRow
{
    if (mSidEmuEngine == NULL) return 0;
    uint_least32_t ms = mSidEmuEngine->timeMs();
    double msPerRow = [self c64MsPerRow];
    if (msPerRow <= 0.0) msPerRow = 120.0;
    int totalRows = (int)(ms / msPerRow);
    return totalRows % 64;
}

- (int) c64CurrentPattern
{
    if (mSidEmuEngine == NULL) return 0;
    uint_least32_t ms = mSidEmuEngine->timeMs();
    double msPerRow = [self c64MsPerRow];
    if (msPerRow <= 0.0) msPerRow = 120.0;
    int totalRows = (int)(ms / msPerRow);
    return (totalRows / 64) % 64;
}

- (int) c64CurrentOrder
{
    if (mSidEmuEngine == NULL) return 0;
    uint_least32_t ms = mSidEmuEngine->timeMs();
    double msPerRow = [self c64MsPerRow];
    if (msPerRow <= 0.0) msPerRow = 120.0;
    int totalRows = (int)(ms / msPerRow);
    return (totalRows / 64);
}

- (int) currentPattern
{
    if (mIsModActive && mModPlayer) return [mModPlayer currentPattern];
    return [self c64CurrentPattern];
}

- (int) currentRow
{
    if (mIsModActive && mModPlayer) return [mModPlayer currentRow];
    return [self c64CurrentRow];
}

- (int) numRowsInCurrentPattern
{
    if (mIsModActive && mModPlayer) return [mModPlayer numRowsInCurrentPattern];
    return 64;
}

- (int) currentOrder
{
    if (mIsModActive && mModPlayer) return [mModPlayer currentOrder];
    return [self c64CurrentOrder];
}

- (int) currentBPM
{
    if (mIsModActive && mModPlayer) return [mModPlayer currentBPM];
    return [self c64CurrentBPM];
}

- (int) currentSpeed
{
    if (mIsModActive && mModPlayer) return [mModPlayer currentSpeed];
    return [self c64CurrentSpeed];
}

- (int) channelMidiNoteForVoice:(int) voice
{
    if (mIsModActive && mModPlayer) return [mModPlayer channelMidiNoteForVoice:voice];
    if (voice < 0 || voice >= 6) return -1;
    if (voice >= 3 && (!mSidEmuEngine || mSidEmuEngine->installedSIDs() <= 1)) return -1;
    if (mixer_muted[voice]) return -1;
    struct SidRegisterFrame* regFrame = (voice >= 3) ? [self getCurrentSidRegisters2] : [self getCurrentSidRegisters];
    if (!regFrame) return -1;
    int regOffset = (voice % 3) * 7;
    uint8_t control = regFrame->mRegisters[regOffset + 4];
    if ((control & 0x01) == 0) return -1; // Gate off
    uint16_t freq = regFrame->mRegisters[regOffset] | (regFrame->mRegisters[regOffset + 1] << 8);
    return SPSidMidiNoteForFrequency(freq);
}

- (int) channelVolumeForVoice:(int) voice
{
    if (mIsModActive && mModPlayer) return [mModPlayer channelVolumeForVoice:voice];
    if (voice < 0 || voice >= 6) return 0;
    if (voice >= 3 && (!mSidEmuEngine || mSidEmuEngine->installedSIDs() <= 1)) return 0;
    if (mixer_muted[voice]) return 0;
    struct SidRegisterFrame* regFrame = (voice >= 3) ? [self getCurrentSidRegisters2] : [self getCurrentSidRegisters];
    if (!regFrame) return 0;
    int regOffset = (voice % 3) * 7;
    uint8_t control = regFrame->mRegisters[regOffset + 4];
    if ((control & 0x01) == 0) return 0;
    uint8_t susRel = regFrame->mRegisters[regOffset + 6];
    uint8_t sustain = (susRel >> 4) & 0x0F;
    return (int)(sustain * 4.26f); // 0..15 -> 0..64
}

- (NSString*) channelEffectForVoice:(int) voice
{
    if (mIsModActive && mModPlayer) return [mModPlayer channelEffectForVoice:voice];
    if (voice < 0 || voice >= 6) return @"...";
    if (voice >= 3 && (!mSidEmuEngine || mSidEmuEngine->installedSIDs() <= 1)) return @"...";
    struct SidRegisterFrame* regFrame = (voice >= 3) ? [self getCurrentSidRegisters2] : [self getCurrentSidRegisters];
    if (!regFrame) return @"...";
    int regOffset = (voice % 3) * 7;
    uint8_t control = regFrame->mRegisters[regOffset + 4];
    uint8_t waveform = control & 0xF0;
    uint16_t pw = (regFrame->mRegisters[regOffset + 2] | (regFrame->mRegisters[regOffset + 3] << 8)) & 0x0FFF;
    if (pw > 0 && (waveform & 0x40)) {
        return [NSString stringWithFormat:@"P%02X", pw >> 4];
    }
    uint8_t filt = regFrame->mRegisters[0x18] >> 4;
    if (filt > 0) {
        return [NSString stringWithFormat:@"F%02X", regFrame->mRegisters[0x16]];
    }
    return @"...";
}

- (void) resetC64TrackerState
{
    sC64LastRecordedPattern = -1;
    sC64LastRecordedRow = -1;
    for (int p = 0; p < 64; p++) {
        for (int r = 0; r < 64; r++) {
            for (int ch = 0; ch < 6; ch++) {
                strcpy(sC64PatternMatrix[p][r][ch].note, "---");
                strcpy(sC64PatternMatrix[p][r][ch].ins, "..");
                strcpy(sC64PatternMatrix[p][r][ch].vol, "..");
                strcpy(sC64PatternMatrix[p][r][ch].fx, "...");
            }
        }
    }
    memset(&currentRegisterFrame, 0, sizeof(currentRegisterFrame));
    memset(&currentRegisterFrame2, 0, sizeof(currentRegisterFrame2));
}

- (void) updateC64PatternMatrix
{
    if (mIsModActive || mSidEmuEngine == NULL) return;
    
    int curPat = [self c64CurrentPattern];
    int curRow = [self c64CurrentRow];
    int curPatIdx = curPat % 64;
    int curRowIdx = curRow % 64;
    
    if (curPat != sC64LastRecordedPattern) {
        for (int r = 0; r < 64; r++) {
            for (int ch = 0; ch < 6; ch++) {
                strcpy(sC64PatternMatrix[curPatIdx][r][ch].note, "---");
                strcpy(sC64PatternMatrix[curPatIdx][r][ch].ins, "..");
                strcpy(sC64PatternMatrix[curPatIdx][r][ch].vol, "..");
                strcpy(sC64PatternMatrix[curPatIdx][r][ch].fx, "...");
            }
        }
        sC64LastRecordedPattern = curPat;
        sC64LastRecordedRow = -1;
    }
    
    mSidEmuEngine->getSidStatus(0, &currentRegisterFrame.mRegisters[0]);
    BOOL hasDualSID = (mSidEmuEngine->installedSIDs() > 1);
    if (hasDualSID) {
        mSidEmuEngine->getSidStatus(1, &currentRegisterFrame2.mRegisters[0]);
    }
    
    int numChannels = hasDualSID ? 6 : 3;
    
    for (int ch = 0; ch < numChannels; ch++) {
        struct SidRegisterFrame* regFrame = (ch >= 3) ? &currentRegisterFrame2 : &currentRegisterFrame;
        int regOffset = (ch % 3) * 7;
        uint8_t control = regFrame->mRegisters[regOffset + 4];
        BOOL gateOn = (control & 0x01) != 0;
        uint16_t freq = regFrame->mRegisters[regOffset] | (regFrame->mRegisters[regOffset + 1] << 8);
        uint8_t waveform = control & 0xF0;
        uint8_t sustain = (regFrame->mRegisters[regOffset + 6] >> 4) & 0x0F;
        
        SPC64TrackerCell &cell = sC64PatternMatrix[curPatIdx][curRowIdx][ch];
        
        if (gateOn) {
            const char* nStr = SPSidNoteStringForFrequency(freq);
            if (nStr && strlen(nStr) > 0) {
                strncpy(cell.note, nStr, sizeof(cell.note) - 1);
                cell.note[sizeof(cell.note) - 1] = '\0';
            }
            
            const char* insStr = "01";
            if (waveform & 0x40) insStr = "03"; // Pulse
            else if (waveform & 0x20) insStr = "02"; // Saw
            else if (waveform & 0x10) insStr = "01"; // Tri
            else if (waveform & 0x80) insStr = "04"; // Noise
            strncpy(cell.ins, insStr, sizeof(cell.ins) - 1);
            cell.ins[sizeof(cell.ins) - 1] = '\0';
            
            int vol = (int)(sustain * 4.26f);
            if (vol > 0) {
                snprintf(cell.vol, sizeof(cell.vol), "%02d", vol);
            } else {
                strcpy(cell.vol, "..");
            }
            
            uint16_t pw = (regFrame->mRegisters[regOffset + 2] | (regFrame->mRegisters[regOffset + 3] << 8)) & 0x0FFF;
            uint8_t filt = regFrame->mRegisters[0x18] >> 4;
            if (pw > 0 && (waveform & 0x40)) {
                snprintf(cell.fx, sizeof(cell.fx), "P%02X", pw >> 4);
            } else if (filt > 0) {
                snprintf(cell.fx, sizeof(cell.fx), "F%02X", regFrame->mRegisters[0x16]);
            } else {
                strcpy(cell.fx, "...");
            }
        }
    }
    
    sC64LastRecordedRow = curRow;
}

- (void) getTrackerCellForChannel:(int)ch row:(int)row note:(NSString* _Nonnull * _Nonnull)outNote ins:(NSString* _Nonnull * _Nonnull)outIns vol:(NSString* _Nonnull * _Nonnull)outVol fx:(NSString* _Nonnull * _Nonnull)outFx
{
    if (mIsModActive && mModPlayer) {
        [mModPlayer getTrackerCellForChannel:ch row:row note:outNote ins:outIns vol:outVol fx:outFx];
        return;
    }
    
    if (ch < 0 || ch >= 6) {
        *outNote = @"---";
        *outIns = @"..";
        *outVol = @"..";
        *outFx = @"...";
        return;
    }
    if (ch >= 3 && (!mSidEmuEngine || mSidEmuEngine->installedSIDs() <= 1)) {
        *outNote = @"---";
        *outIns = @"..";
        *outVol = @"..";
        *outFx = @"...";
        return;
    }
    
    int curPatIdx = [self c64CurrentPattern] % 64;
    int curRow = [self c64CurrentRow];
    
    if (row == curRow) {
        SPC64TrackerCell &cell = sC64PatternMatrix[curPatIdx][curRow % 64][ch];
        if (strcmp(cell.note, "---") != 0) {
            *outNote = [NSString stringWithUTF8String:cell.note];
            *outIns = [NSString stringWithUTF8String:cell.ins];
            *outVol = [NSString stringWithUTF8String:cell.vol];
            *outFx = [NSString stringWithUTF8String:cell.fx];
        } else {
            NSString *liveNote = [self channelNoteForVoice:ch];
            if (![liveNote isEqualToString:@"--"] && ![liveNote isEqualToString:@"---"]) {
                *outNote = liveNote;
                *outIns = @"01";
                int v = [self channelVolumeForVoice:ch];
                *outVol = (v > 0) ? [NSString stringWithFormat:@"%02d", v] : @"..";
                *outFx = [self channelEffectForVoice:ch];
            } else {
                *outNote = @"---";
                *outIns = @"..";
                *outVol = @"..";
                *outFx = @"...";
            }
        }
        return;
    }
    
    if (row >= 0 && row < 64) {
        SPC64TrackerCell &cell = sC64PatternMatrix[curPatIdx][row][ch];
        *outNote = [NSString stringWithUTF8String:cell.note];
        *outIns = [NSString stringWithUTF8String:cell.ins];
        *outVol = [NSString stringWithUTF8String:cell.vol];
        *outFx = [NSString stringWithUTF8String:cell.fx];
        return;
    }
    
    *outNote = @"---";
    *outIns = @"..";
    *outVol = @"..";
    *outFx = @"...";
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

- (void) seekToSeconds:(int)targetSeconds
{
    if (mIsModActive && mModPlayer) {
        [mModPlayer seekToSeconds:targetSeconds];
        return;
    }
    
    if (mSidEmuEngine == NULL || mSidTune == NULL)
        return;
    
    if (targetSeconds <= 0) {
        [self initCurrentSubtune];
        return;
    }
    
    int currentSecs = (int)mSidEmuEngine->time();
    if (targetSeconds < currentSecs) {
        [self initCurrentSubtune];
        currentSecs = 0;
    }
    
    unsigned int sampleRate = mPlaybackSettings.mFrequency > 0 ? mPlaybackSettings.mFrequency : 44100;
    int secsToAdvance = targetSeconds - currentSecs;
    if (secsToAdvance > 0) {
        short discardBuffer[4096];
        int totalSamplesToRun = secsToAdvance * sampleRate;
        while (totalSamplesToRun > 0) {
            int chunk = MIN(totalSamplesToRun, 4096);
            mSidEmuEngine->play(discardBuffer, chunk);
            totalSamplesToRun -= chunk;
            if ((int)mSidEmuEngine->time() >= targetSeconds) break;
        }
    }
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
    [self resetC64TrackerState];
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
        
        int oversampledCount16 = count16 * mPlaybackSettings.mOversampling;
        if (!mExtUSBDeviceActive)
            mSidEmuEngine->play((short *)mOversamplingBuffer, oversampledCount16);
        
        short *oversampleBuffer = (short*) mOversamplingBuffer;
        short *outputBuffer = (short*) buffer;
        int os = mPlaybackSettings.mOversampling;
        
        BOOL isStereo = (mPlaybackSettings.mStereo || (mTuneInfo && mTuneInfo->sidChips() > 1));
        if (isStereo) {
            int frameCount = count16 / 2;
            for (int f = 0; f < frameCount; f++) {
                long sumL = 0;
                long sumR = 0;
                for (int i = 0; i < os; i++) {
                    sumL += *oversampleBuffer++;
                    sumR += *oversampleBuffer++;
                }
                *outputBuffer++ = (short)(sumL / os);
                *outputBuffer++ = (short)(sumR / os);
            }
        } else {
            for (int sampleCount = count16; sampleCount > 0; sampleCount--) {
                long sample = 0;
                for (int i = 0; i < os; i++) {
                    sample += *oversampleBuffer++;
                }
                *outputBuffer++ = (short)(sample / os);
            }
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
        if (mSidEmuEngine->installedSIDs() > 1) {
            mSidEmuEngine->getSidStatus(1, &currentRegisterFrame2.mRegisters[0]);
        }
        return &currentRegisterFrame;
    }
    else
        return &currentRegisterFrame;
}

- (struct SidRegisterFrame*) getCurrentSidRegisters2
{
    if (mSidEmuEngine != NULL && mSidEmuEngine->installedSIDs() > 1) {
        mSidEmuEngine->getSidStatus(1, &currentRegisterFrame2.mRegisters[0]);
        return &currentRegisterFrame2;
    }
    return nil;
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
