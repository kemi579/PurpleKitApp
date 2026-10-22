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
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { return }
        loading = true
        error = nil
        results = []
        DispatchQueue.global().async {
            var hints = addrinfo(ai_flags: AI_PASSIVE, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
            var res: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(h, nil, &hints, &res)
            defer { freeaddrinfo(res) }
            DispatchQueue.main.async {
                if status == 0, let res = res {
                    var list: [String] = []
                    var ptr: UnsafeMutablePointer<addrinfo>? = res
                    while let p = ptr {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(p.pointee.ai_addr, p.pointee.ai_addrlen, &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                            list.append(String(cString: hostname))
                        }
                        ptr = p.pointee.ai_next
                    }
                    if !list.isEmpty {
                        results = Array(Set(list)).sorted()
                        Haptic.success()
                    } else {
                        error = "No addresses"
                        Haptic.error()
                    }
                } else {
                    error = "Lookup failed"
                    Haptic.error()
                }
                loading = false
            }
        }
    }
}
