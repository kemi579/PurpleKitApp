import SwiftUI
import Network

struct DNSLookupTool: Tool {
    let id = "dns"
    let name = "DNS Lookup"
    let icon = "server.rack"
    let category: ToolCategory = .network
    let description = "Resolve hostname to IP"

    var content: AnyView { AnyView(DNSLookupView()) }
}

struct DNSLookupView: View {
    @State private var host = ""
    @State private var results: [String] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PurpleTextField(placeholder: "Hostname (e.g. google.com)", text: $host)

                PurpleButton(title: "Lookup", icon: "magnifyingglass") {
                    lookup()
                }

                if loading {
                    ProgressView().tint(Theme.primaryLight)
                }

                if let error {
                    Text(error).font(.caption).foregroundColor(Theme.error)
                }

                ForEach(results, id: \.self) { r in
                    ResultBox(title: "Address", value: r) {}
                }
            }
            .padding()
        }
    }

    private func lookup() {
        let hostname = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hostname.isEmpty else { return }
        loading = true
        error = nil
        results = []

        DispatchQueue.global(qos: .userInitiated).async {
            var hints = addrinfo(
                ai_flags: AI_PASSIVE,
                ai_family: AF_UNSPEC,
                ai_socktype: SOCK_STREAM,
                ai_protocol: 0,
                ai_addrlen: 0,
                ai_canonname: nil,
                ai_addr: nil,
                ai_next: nil
            )
            var resultPointer: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(hostname, nil, &hints, &resultPointer)

            var addresses: [String] = []
            if status == 0, let first = resultPointer {
                var current: UnsafeMutablePointer<addrinfo>? = first
                while let entry = current {
                    var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(
                        entry.pointee.ai_addr,
                        entry.pointee.ai_addrlen,
                        &buffer,
                        socklen_t(buffer.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    ) == 0 {
                        let length = buffer.firstIndex(of: 0) ?? buffer.endIndex
                        let bytes = buffer[..<length].map { UInt8(bitPattern: $0) }
                        addresses.append(String(decoding: bytes, as: UTF8.self))
                    }
                    current = entry.pointee.ai_next
                }
            }
            freeaddrinfo(resultPointer)

            let uniqueAddresses = Array(Set(addresses)).sorted()
            DispatchQueue.main.async {
                if status == 0, !uniqueAddresses.isEmpty {
                    results = uniqueAddresses
                    Haptic.success()
                } else {
                    error = status == 0 ? "No addresses" : "Lookup failed"
                    Haptic.error()
                }
                loading = false
            }
        }
    }
}
