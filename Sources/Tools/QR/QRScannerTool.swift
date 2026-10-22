import SwiftUI
import AVFoundation

struct QRScannerTool: Tool {
    let id = "qrscan"
    let name = "QR Scanner"
    let icon = "qrcode.viewfinder"
    let category: ToolCategory = .qr
    let description = "Scan QR codes with camera"

    var content: AnyView { AnyView(QRScannerView()) }
}

struct QRScannerView: View {
    @State private var scanned = ""
    @State private var isScanning = true
    @State private var permissionDenied = false

    var body: some View {
        VStack(spacing: 0) {
            if permissionDenied {
                EmptyStateView(icon: "camera.fill", title: "Camera Access Needed", message: "Enable camera in Settings to scan QR codes.")
            } else {
                ZStack {
                    QRScannerRepresentable(scannedCode: $scanned, isScanning: $isScanning)
                        .ignoresSafeArea(edges: .bottom)

                    VStack {
                        Spacer()
                        if !scanned.isEmpty {
                            VStack(spacing: 12) {
                                ResultBox(title: "Scanned", value: scanned) {}
                                HStack {
                                    PurpleButton(title: "Copy", icon: "doc.on.doc") {
                                        UIPasteboard.general.string = scanned
                                        Haptic.success()
                                    }
                                    PurpleButton(title: "Scan Again", icon: "arrow.clockwise", style: .secondary) {
                                        scanned = ""
                                        isScanning = true
                                    }
                                }
                            }
                            .padding()
                            .background(Theme.background.opacity(0.95))
                        }
                    }
                }
            }
        }
        .onAppear {
            checkPermission()
        }
    }

    private func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionDenied = false
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    permissionDenied = !granted
                }
            }
        default:
            permissionDenied = true
        }
    }
}

struct QRScannerRepresentable: UIViewControllerRepresentable {
    @Binding var scannedCode: String
    @Binding var isScanning: Bool

    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerVC, context: Context) {
        if isScanning {
            uiViewController.start()
        } else {
            uiViewController.stop()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, ScannerVCDelegate {
        var parent: QRScannerRepresentable
        init(_ parent: QRScannerRepresentable) { self.parent = parent }
        func didScan(_ code: String) {
            parent.scannedCode = code
            parent.isScanning = false
            Haptic.success()
        }
    }
}

protocol ScannerVCDelegate: AnyObject {
    func didScan(_ code: String)
}

class ScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: ScannerVCDelegate?
    private var session: AVCaptureSession?
    private var preview: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setup()
    }

    private func setup() {
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
        }
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.layer.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        self.session = session
        self.preview = preview
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.session?.startRunning()
        }
    }

    func stop() {
        session?.stopRunning()
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue else { return }
        session?.stopRunning()
        delegate?.didScan(value)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.layer.bounds
    }
}
