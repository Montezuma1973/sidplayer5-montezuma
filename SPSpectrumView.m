#import "SPSpectrumView.h"
#import <math.h>

static const int kSpectrumFFTSize = 1024;
static const int kSpectrumBarCount = 8;

@implementation SPSpectrumView
{
    float _barLevels[kSpectrumBarCount];
    float _window[kSpectrumFFTSize];
    float _real[kSpectrumFFTSize];
    float _imag[kSpectrumFFTSize];
    float _magnitudes[kSpectrumFFTSize / 2];
    BOOL _windowReady;
}

// ----------------------------------------------------------------------------
- (instancetype)initWithFrame:(NSRect)frame
// ----------------------------------------------------------------------------
{
    self = [super initWithFrame:frame];
    if (self) {
        for (int i = 0; i < kSpectrumBarCount; i++) {
            _barLevels[i] = 0.0f;
        }
        _windowReady = NO;
    }
    return self;
}

// ----------------------------------------------------------------------------
- (BOOL)isFlipped
// ----------------------------------------------------------------------------
{
    return YES;
}

// ----------------------------------------------------------------------------
static void SPComputeHannWindow(float *window, int size)
// ----------------------------------------------------------------------------
{
    const float twoPi = 2.0f * (float)M_PI;
    for (int i = 0; i < size; i++) {
        window[i] = 0.5f * (1.0f - cosf(twoPi * (float)i / (float)(size - 1)));
    }
}

// ----------------------------------------------------------------------------
static void SPFFT(float *real, float *imag, int size)
// ----------------------------------------------------------------------------
{
    int j = 0;
    for (int i = 1; i < size; i++) {
        int bit = size >> 1;
        for (; j & bit; bit >>= 1) {
            j ^= bit;
        }
        j ^= bit;
        if (i < j) {
            float temp = real[i];
            real[i] = real[j];
            real[j] = temp;
            temp = imag[i];
            imag[i] = imag[j];
            imag[j] = temp;
        }
    }

    for (int len = 2; len <= size; len <<= 1) {
        float angle = -2.0f * (float)M_PI / (float)len;
        float wlenCos = cosf(angle);
        float wlenSin = sinf(angle);
        for (int i = 0; i < size; i += len) {
            float wCos = 1.0f;
            float wSin = 0.0f;
            int half = len >> 1;
            for (int j2 = 0; j2 < half; j2++) {
                int u = i + j2;
                int v = u + half;
                float realV = real[v] * wCos - imag[v] * wSin;
                float imagV = real[v] * wSin + imag[v] * wCos;
                real[v] = real[u] - realV;
                imag[v] = imag[u] - imagV;
                real[u] += realV;
                imag[u] += imagV;
                float nextCos = wCos * wlenCos - wSin * wlenSin;
                float nextSin = wCos * wlenSin + wSin * wlenCos;
                wCos = nextCos;
                wSin = nextSin;
            }
        }
    }
}

// ----------------------------------------------------------------------------
- (void)updateWithSamples:(const short *)samples count:(int)count sampleRate:(int)sampleRate
// ----------------------------------------------------------------------------
{
    if (samples == NULL || count <= 0) {
        return;
    }

    if (!_windowReady) {
        SPComputeHannWindow(_window, kSpectrumFFTSize);
        _windowReady = YES;
    }

    int copyCount = count >= kSpectrumFFTSize ? kSpectrumFFTSize : count;
    int startIndex = count - copyCount;

    for (int i = 0; i < kSpectrumFFTSize; i++) {
        float sample = 0.0f;
        if (i < copyCount) {
            sample = (float)samples[startIndex + i] / 32768.0f;
        }
        _real[i] = sample * _window[i];
        _imag[i] = 0.0f;
    }

    SPFFT(_real, _imag, kSpectrumFFTSize);

    for (int i = 0; i < kSpectrumFFTSize / 2; i++) {
        float real = _real[i];
        float imag = _imag[i];
        _magnitudes[i] = sqrtf(real * real + imag * imag);
    }

    float nyquist = (float)sampleRate * 0.5f;
    float minFreq = 31.0f;
    float maxFreq = nyquist < 12000.0f ? nyquist : 12000.0f;

    for (int i = 0; i < kSpectrumBarCount; i++) {
        float low = minFreq * powf(2.0f, (float)i);
        float high = low * 2.0f;
        if (low >= maxFreq) {
            _barLevels[i] = 0.0f;
            continue;
        }
        if (high > maxFreq) {
            high = maxFreq;
        }
        int lowBin = (int)floorf(low * (float)kSpectrumFFTSize / (float)sampleRate);
        int highBin = (int)floorf(high * (float)kSpectrumFFTSize / (float)sampleRate);

        if (lowBin < 1) {
            lowBin = 1;
        }
        if (highBin <= lowBin) {
            highBin = lowBin + 1;
        }
        int maxBin = (kSpectrumFFTSize / 2) - 1;
        if (highBin > maxBin) {
            highBin = maxBin;
        }

        float sum = 0.0f;
        int bins = highBin - lowBin + 1;
        for (int bin = lowBin; bin <= highBin; bin++) {
            sum += _magnitudes[bin];
        }
        float avg = sum / (float)bins;
        avg /= (float)kSpectrumFFTSize;
        float db = 20.0f * log10f(avg + 1e-9f);
        float normalized = (db + 90.0f) / 80.0f;
        if (normalized < 0.0f) {
            normalized = 0.0f;
        } else if (normalized > 1.0f) {
            normalized = 1.0f;
        }

        if (normalized > _barLevels[i]) {
            _barLevels[i] = normalized;
        } else {
            _barLevels[i] = _barLevels[i] * 0.85f + normalized * 0.15f;
        }
    }

    [self setNeedsDisplay:YES];
}

// ----------------------------------------------------------------------------
- (void)drawRect:(NSRect)dirtyRect
// ----------------------------------------------------------------------------
{
    NSRect bounds = self.bounds;
    [[NSColor controlBackgroundColor] setFill];
    NSRectFill(bounds);

    if (bounds.size.width <= 0.0f || bounds.size.height <= 0.0f) {
        return;
    }

    CGFloat gap = 2.0f;
    CGFloat totalGap = gap * (kSpectrumBarCount + 1);
    CGFloat barWidth = (bounds.size.width - totalGap) / (CGFloat)kSpectrumBarCount;
    if (barWidth < 1.0f) {
        barWidth = 1.0f;
    }

    CGFloat maxHeight = bounds.size.height - 4.0f;
    CGFloat originY = 2.0f;
    CGFloat inset = 3.0f;

    CGFloat trackRadius = MIN(barWidth, maxHeight) * 0.2f;
    if (trackRadius < 2.0f) {
        trackRadius = 2.0f;
    }
    for (int i = 0; i < kSpectrumBarCount; i++) {
        CGFloat level = _barLevels[i];
        CGFloat innerHeight = maxHeight - inset * 2.0f;
        if (innerHeight < 1.0f) {
            innerHeight = 1.0f;
        }
        CGFloat barHeight = innerHeight * level;
        CGFloat x = gap + (barWidth + gap) * (CGFloat)i;
        NSRect backRect = NSMakeRect(x, originY, barWidth, maxHeight);
        [[NSColor blackColor] setFill];
        NSBezierPath *trackPath = [NSBezierPath bezierPathWithRoundedRect:backRect
                                                                  xRadius:trackRadius
                                                                  yRadius:trackRadius];
        [trackPath fill];

        CGFloat innerWidth = barWidth - inset * 2.0f;
        if (innerWidth < 1.0f) {
            innerWidth = 1.0f;
        }
        CGFloat innerY = originY + inset;
        CGFloat barTop = innerY + (innerHeight - barHeight);
        CGFloat barBottom = innerY + innerHeight;
        NSRect barRect = NSMakeRect(x + inset,
                                    barTop,
                                    innerWidth,
                                    barHeight);
        float t = kSpectrumBarCount > 1 ? (float)i / (float)(kSpectrumBarCount - 1) : 0.0f;
        NSColor *barColor = [NSColor colorWithDeviceRed:(1.0f - t) green:0.0f blue:t alpha:1.0f];
        NSColor *glowColor = [NSColor colorWithDeviceRed:(1.0f - t) green:0.0f blue:t alpha:0.55f];
        CGFloat segmentHeight = 10.0f;
        CGFloat segmentGap = 3.0f;
        CGFloat segmentStride = segmentHeight + segmentGap;
        CGFloat segmentRadius = MIN(innerWidth, segmentHeight) * 0.25f;
        if (segmentRadius < 1.0f) {
            segmentRadius = 1.0f;
        }

        NSGraphicsContext *context = [NSGraphicsContext currentContext];
        [context saveGraphicsState];
        NSShadow *shadow = [[NSShadow alloc] init];
        shadow.shadowColor = glowColor;
        shadow.shadowBlurRadius = 6.0f;
        shadow.shadowOffset = NSMakeSize(0.0f, 0.0f);
        [shadow set];
        [barColor setFill];

        for (CGFloat y = barBottom - segmentHeight; y >= barTop; y -= segmentStride) {
            CGFloat visibleHeight = segmentHeight;
            if (y < barTop) {
                visibleHeight = segmentHeight - (barTop - y);
                y = barTop;
            }
            if (visibleHeight <= 0.0f) {
                break;
            }
            NSRect segmentRect = NSMakeRect(barRect.origin.x, y, barRect.size.width, visibleHeight);
            NSBezierPath *segmentPath = [NSBezierPath bezierPathWithRoundedRect:segmentRect
                                                                        xRadius:segmentRadius
                                                                        yRadius:segmentRadius];
            [segmentPath fill];
        }
        [context restoreGraphicsState];

        [barColor setFill];
        for (CGFloat y = barBottom - segmentHeight; y >= barTop; y -= segmentStride) {
            CGFloat visibleHeight = segmentHeight;
            if (y < barTop) {
                visibleHeight = segmentHeight - (barTop - y);
                y = barTop;
            }
            if (visibleHeight <= 0.0f) {
                break;
            }
            NSRect segmentRect = NSMakeRect(barRect.origin.x, y, barRect.size.width, visibleHeight);
            NSBezierPath *segmentPath = [NSBezierPath bezierPathWithRoundedRect:segmentRect
                                                                        xRadius:segmentRadius
                                                                        yRadius:segmentRadius];
            [segmentPath fill];
        }
    }
}

@end
