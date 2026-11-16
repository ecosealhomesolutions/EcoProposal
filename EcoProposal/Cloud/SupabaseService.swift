import Foundation
import Supabase

/// Shared connection to the EcoProposal Supabase project (the same database the
/// web app uses).
///
/// The publishable key is safe to ship inside the app: every table is protected
/// by row-level security, so the key by itself can't read or change anything.
/// What a user can see or edit is decided by their signed-in role.
enum SupabaseService {
    static let url = URL(string: "https://lmbcpyfgrlebtkjcugrz.supabase.co")!
    static let publishableKey = "sb_publishable_2wv7CUChRCHeI7E4zHdVbg_1hbCFe7R"

    /// Where Microsoft sign-in returns to. Must also be listed in Supabase under
    /// Authentication → URL Configuration → Redirect URLs.
    static let authRedirectURL = URL(string: "ecoproposal://login-callback")!

    static let client = SupabaseClient(
        supabaseURL: url,
        supabaseKey: publishableKey,
        options: SupabaseClientOptions(
            // Opt in to the library's upcoming default (silences its console warning).
            // CloudSession always validates/refreshes the session itself, so an
            // expired saved session is handled either way.
            auth: SupabaseClientOptions.AuthOptions(emitLocalSessionAsInitialSession: true)
        )
    )
}
