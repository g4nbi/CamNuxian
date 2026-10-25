// NyxCamera - simple camera app for Nyxian (Objective-C, no storyboard)
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>

@interface CamVC : UIViewController <AVCapturePhotoCaptureDelegate>
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureDeviceInput *input;
@property (nonatomic, strong) AVCapturePhotoOutput *photoOut;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *preview;
@property (nonatomic, assign) AVCaptureDevicePosition pos;
@property (nonatomic, strong) UIButton *shutter, *flip;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) dispatch_queue_t q;
@end

@implementation CamVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.pos = AVCaptureDevicePositionBack;
    self.q = dispatch_queue_create("nyxcam.session", DISPATCH_QUEUE_SERIAL);

    self.status = [UILabel new];
    self.status.textColor = UIColor.whiteColor;
    self.status.textAlignment = NSTextAlignmentCenter;
    self.status.numberOfLines = 0;
    self.status.font = [UIFont systemFontOfSize:14];
    [self.view addSubview:self.status];

    self.shutter = [UIButton buttonWithType:UIButtonTypeCustom];
    self.shutter.backgroundColor = UIColor.whiteColor;
    self.shutter.layer.cornerRadius = 35;
    self.shutter.layer.borderWidth = 4;
    self.shutter.layer.borderColor = [UIColor colorWithWhite:0.6 alpha:1].CGColor;
    [self.shutter addTarget:self action:@selector(shoot) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.shutter];

    self.flip = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.flip setTitle:@"Flip" forState:UIControlStateNormal];
    [self.flip setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.flip.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [self.flip addTarget:self action:@selector(flipCam) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.flip];

    __weak typeof(self) ws = self;
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (granted) [ws setup];
            else ws.status.text = @"Izin kamera ditolak.\nAktifkan di Settings atau cek entitlement Nyxian.";
        });
    }];
}

- (BOOL)attachInput {
    AVCaptureDevice *dev = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                                              mediaType:AVMediaTypeVideo
                                                               position:self.pos];
    if (!dev) { self.status.text = @"Kamera tidak ditemukan"; return NO; }
    NSError *err = nil;
    AVCaptureDeviceInput *in = [AVCaptureDeviceInput deviceInputWithDevice:dev error:&err];
    if (!in || ![self.session canAddInput:in]) {
        self.status.text = [NSString stringWithFormat:@"Gagal buka kamera: %@", err.localizedDescription ?: @"unknown"];
        return NO;
    }
    [self.session addInput:in];
    self.input = in;
    return YES;
}

- (void)setup {
    self.session = [AVCaptureSession new];
    self.session.sessionPreset = AVCaptureSessionPresetPhoto;
    if (![self attachInput]) return;

    self.photoOut = [AVCapturePhotoOutput new];
    if ([self.session canAddOutput:self.photoOut]) [self.session addOutput:self.photoOut];

    self.preview = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    self.preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer insertSublayer:self.preview atIndex:0];
    [self.view setNeedsLayout];

    dispatch_async(self.q, ^{ [self.session startRunning]; });
}

- (void)flipCam {
    if (!self.session) return;
    self.pos = (self.pos == AVCaptureDevicePositionBack) ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
    dispatch_async(self.q, ^{
        [self.session beginConfiguration];
        if (self.input) [self.session removeInput:self.input];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self attachInput];
            dispatch_async(self.q, ^{ [self.session commitConfiguration]; });
        });
    });
}

- (void)shoot {
    if (!self.photoOut) return;
    AVCapturePhotoSettings *s = [AVCapturePhotoSettings photoSettings];
    [self.photoOut capturePhotoWithSettings:s delegate:self];
    self.view.alpha = 0.4;
    [UIView animateWithDuration:0.2 animations:^{ self.view.alpha = 1; }];
}

- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {
    if (error) { dispatch_async(dispatch_get_main_queue(), ^{ self.status.text = error.localizedDescription; }); return; }
    NSData *data = [photo fileDataRepresentation];
    if (!data) return;

    // 1) Always save a copy in app Documents
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"yyyyMMdd_HHmmss";
    NSString *path = [docs stringByAppendingPathComponent:[NSString stringWithFormat:@"IMG_%@.jpg", [f stringFromDate:[NSDate date]]]];
    [data writeToFile:path atomically:YES];

    // 2) Try saving to Photos
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus st) {
        if (st != PHAuthorizationStatusAuthorized && st != PHAuthorizationStatusLimited) {
            dispatch_async(dispatch_get_main_queue(), ^{ self.status.text = @"Tersimpan di Documents (Photos ditolak)"; });
            return;
        }
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            PHAssetCreationRequest *r = [PHAssetCreationRequest creationRequestForAsset];
            [r addResourceWithType:PHAssetResourceTypePhoto data:data options:nil];
        } completionHandler:^(BOOL ok, NSError *e) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.status.text = ok ? @"Tersimpan ke Photos" : @"Tersimpan di Documents";
            });
        }];
    }];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    UIEdgeInsets sa = self.view.safeAreaInsets;
    self.preview.frame = b;
    self.shutter.frame = CGRectMake((b.size.width - 70) / 2, b.size.height - sa.bottom - 100, 70, 70);
    self.flip.frame = CGRectMake(b.size.width - 90, b.size.height - sa.bottom - 85, 70, 40);
    self.status.frame = CGRectMake(16, sa.top + 8, b.size.width - 32, 50);
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }
- (BOOL)prefersStatusBarHidden { return YES; }
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [CamVC new];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
