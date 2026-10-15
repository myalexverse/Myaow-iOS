import Foundation

@main struct SupabaseRouteChecks {
 static func main() throws {
  let address="https://your-project-ref.supabase.co/functions/v1/myaow-api"
  let endpoint=RelayEndpoint(address)!
  precondition(endpoint.httpURL.absoluteString==address && endpoint.supabaseAPIURL==endpoint.httpURL)
  precondition(RelayEndpoint("http://your-project-ref.supabase.co/functions/v1/myaow-api")==nil)
  precondition(RelayEndpoint("https://example.com/ws")!.httpURL.absoluteString=="https://example.com")
  let id=UUID().uuidString
  let cases:[(String,String,String)]=[
   ("/api/v1/calls/signal","POST","calls/signal"),
   ("/api/v1/webrtc/ice-servers","GET","webrtc/ice-servers"),
   ("/api/v1/push/device","PUT","push/device"),
   ("/api/v1/groups/create","POST","groups/create"),
   ("/api/v1/groups/my/MYAOW-TEST","GET","groups/list"),
   ("/api/v1/groups/\(id)/members","GET","groups/members"),
   ("/api/v1/groups/\(id)/tasks","GET","tasks/list"),
   ("/api/v1/groups/\(id)/tasks","POST","tasks/create"),
   ("/api/v1/tasks/\(id)/complete","PUT","tasks/update"),
   ("/api/v1/tasks/\(id)","DELETE","tasks/delete"),
   ("/api/v1/scheduled-v2","POST","schedules/create"),
   ("/api/v1/scheduled-v2","GET","schedules/list"),
   ("/api/v1/scheduled-v2/\(id)","DELETE","schedules/cancel"),
   ("/api/v1/messages-v2/batch","POST","messages/batch"),
   ("/api/v1/contacts/blocked/MYAOW-TEST","GET","contacts/blocked")]
  for (path,method,expected) in cases { let route = try SupabaseRoute(path,method:method); precondition(route.path==expected) }
  let accept=try SupabaseRoute("/api/v1/groups/invite/accept",method:"POST",body:["token":"invitation-code"])
  precondition(accept.body["inviteId"] as? String=="invitation-code")
  let kick=try SupabaseRoute("/api/v1/groups/\(id)/kick",method:"POST",body:["targetMyaowId":"MYAOW-PEER"])
  precondition(kick.body["target"] as? String=="MYAOW-PEER" && kick.body["groupId"] as? String==id.lowercased())
  for (path,method) in [("/api/v1/groups/\(id)/join","POST"),("/api/v1/calls/signal","GET"),("/api/v1/groups/\(id)/kick","GET"),("https://evil.invalid","POST")] {
   do { _ = try SupabaseRoute(path,method:method); preconditionFailure("Unsupported route accepted") }
   catch let error as SupabaseHTTPError { precondition(error.status==501) }
  }
  print("PASS: Supabase endpoint prefix, HTTPS, legacy relay compatibility, feature route/method mapping, targeted invitations and unsupported features fail closed.")
 }
}
