import Foundation

@main struct VideoChecks {
 static func main() throws {
  let legacy=try JSONDecoder().decode(DraftPhoto.self,from:Data(#"{"id":"photo","caption":"음식"}"#.utf8))
  precondition(!legacy.isVideo && legacy.marker(1)=="[사진 1]")
  let video=DraftPhoto(id:"video",caption:"끓는 국물",mediaType:"video")
  let image=DraftPhoto(id:"photo",caption:"음식")
  let photos=[image,video]
  let text="제목\n\n설명 😊\n[사진 1]\n영상 설명\n[영상 2]\n\n#후기"
  precondition(DraftLayout.warnings(text:text,photos:photos).isEmpty)
  precondition(DraftLayout.blocks(text).filter(\.isVideo).map(\.photoNumber)==[2])
  precondition(!DraftLayout.warnings(text:text.replacingOccurrences(of:"[영상 2]",with:"[사진 2]"),photos:photos).isEmpty)
  precondition(!DraftLayout.warnings(text:text+"\n[영상 2]",photos:photos).isEmpty)
  let moved=try DraftLayout.reconnect(text:text,from:photos,to:[video,image])
  precondition(moved.contains("[사진 2]")&&moved.contains("[영상 1]"))
  let removed=try DraftLayout.reconnect(text:text,from:photos,to:[video])
  precondition(!removed.contains("[사진 1]")&&removed.contains("[영상 1]"))
  let added=try DraftLayout.reconnect(text:"제목\n[사진 1]\n#후기",from:[image],to:photos)
  precondition(added.contains("[영상 2]")&&added.hasSuffix("#후기"))
  var review=VisitReview();review.photoIDs=["photo","video"];review.videoIDs=["video"]
  review.restaurantName="가게";review.visitDate=Date(timeIntervalSince1970:1700000000)
  review.menus=[ReviewMenu(name:"국물",impression:"뜨거웠어요",photoIDs:review.photoIDs)]
  precondition(MenuDraftPhotos.make(review:review).map(\.isVideo)==[false,true])
  let encoded=try JSONEncoder().encode(review)
  let restored=try JSONDecoder().decode(VisitReview.self,from:encoded)
  precondition(restored==review)
  var object=try JSONSerialization.jsonObject(with:encoded) as! [String:Any];object.removeValue(forKey:"videoIDs")
  let old=try JSONDecoder().decode(VisitReview.self,from:JSONSerialization.data(withJSONObject:object))
  precondition(old.videoIDs.isEmpty)
  var plan=DraftPhotoPlan(selected:photos,requestPhotos:photos,requestReview:review)
  _=plan.syncMenuPhotos(review:review)
  precondition(plan.requestPhotos==photos)
  let planRestored=try JSONDecoder().decode(DraftPhotoPlan.self,from:JSONEncoder().encode(plan))
  precondition(planRestored.selected.last?.isVideo==true)
  for template in DraftTemplate.allCases {
   let packet=try NaverPostPacket.make(text:text,photos:photos,filenames:["01_사진.jpg","02_영상.mp4"],template:template,review:review)
   precondition(packet.version==3 && packet.photos[1].mediaType=="video")
   precondition(packet.blocks.filter{$0.kind=="video"}.map(\.photoNumber)==[2])
   precondition(packet.blocks.filter{$0.kind=="photo"}.map(\.photoNumber)==[1])
   precondition((packet.blocks.first?.paragraphs != nil)==(template == .record))
   let decoded=try JSONDecoder().decode(NaverPostPacket.self,from:JSONEncoder().encode(packet))
   precondition(decoded.photos.last?.isVideo==true)
   let prompt=try DraftPrompt.make(review:review,references:nil,photos:photos,template:template)
   let json=prompt.components(separatedBy:"순서대로 배치할 사진 목록 JSON:\n")[1].components(separatedBy:"\n\n문체 참고 글 JSON:")[0]
   let metadata=try JSONSerialization.jsonObject(with:Data(json.utf8)) as! [[String:Any]]
   precondition(metadata[1]["marker"] as? String == "[영상 2]" && metadata[1]["mediaType"] as? String == "video")
   precondition(!prompt.contains("\"id\""))
  }
  do{_=try NaverPostPacket.make(text:text.replacingOccurrences(of:"[영상 2]",with:"[사진 2]"),photos:photos,filenames:["01_사진.jpg","02_영상.mp4"]);fatalError("Accepted wrong kind")}catch{}
  let many=(1...11).map{DraftPhoto(id:"v\($0)",mediaType:"video")}
  do{_=try NaverPostPacket.make(text:"제목\n본문\n"+many.enumerated().map{$0.element.marker($0.offset+1)}.joined(separator:"\n"),photos:many,filenames:many.indices.map{"\($0).mp4"});fatalError("Accepted 11 videos")}catch{}
  let oldPacket=try NaverPostPacket.make(text:"제목\n본문\n[사진 1]",photos:[image],filenames:["01_사진.jpg"],template:.record)
  precondition(oldPacket.version==2)
  print("Passed legacy media decoding, video selection/snapshots, typed markers/reorder/removal, mixed v3 packets/templates, privacy and video count rejection")
 }
}
