"""Small deterministic contract checks for the removable mock box."""

import server


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    thumbnail = server.mock_bird_bmp(1, preview=False)
    preview = server.mock_bird_bmp(1, preview=True)
    check(thumbnail[:2] == b"BM" and preview[:2] == b"BM", "mock media must be valid BMP data")
    check(len(preview) > len(thumbnail), "preview media should be larger than thumbnails")
    check(server.photos[0]["thumb_ref"].startswith("__MOCK_ORIGIN__"), "photo media should use a request-scoped origin marker")
    resolved = server.resolve_media_origin(server.read_page({"page_size": ["1"]}), "http://192.168.8.20:8080")
    check(resolved["items"][0]["thumb_ref"].startswith("http://192.168.8.20:8080/"), "LAN clients must receive their requested media origin")
    check(all(0 <= item["rating"]["total_score"] <= 5 for item in server.photos[:100]), "mock ratings must use a five-point scale")

    current = server.payload("/api/v1/projects/current", "GET", {}, {})
    check(current["pending_review_count"] == current["review_count"], "current batch must expose the canonical pending review count")

    search = server.read_page({"search": ["白鹭"], "page_size": ["20"]})
    check(search["items"], "species search should return results")
    check(all(item["recognition"]["species_topn"][0]["name"] == "白鹭" for item in search["items"]), "search result mismatch")

    confidence = server.read_page({"sort": ["confidence_desc"], "page_size": ["30"]})["items"]
    values = [item["recognition"]["species_topn"][0]["confidence"] for item in confidence]
    check(values == sorted(values, reverse=True), "confidence_desc must be descending")

    scenes = server.payload(f"/api/v1/projects/{server.BATCH_ID}/scenes", "GET", {}, {})["items"]
    check(len(scenes) == 4 and all(item["photo_count"] > 0 for item in scenes), "scene contract mismatch")
    groups = server.payload(f"/api/v1/projects/{server.BATCH_ID}/groups", "GET", {"scene_id": ["scene-demo-001"]}, {})["items"]
    check(groups and all(item["scene_id"] == "scene-demo-001" for item in groups), "scene group filter mismatch")
    species = server.payload("/api/v1/species", "GET", {"search": ["翠"]}, {})["items"]
    check(species and all("species_id" in item for item in species), "species search contract mismatch")
    clarity = server.read_page({"clarity_state": ["blurred"], "page_size": ["10"]})["items"]
    check(clarity and all(item["clarity_state"] == "blurred" for item in clarity), "clarity filter mismatch")
    recommended = server.read_page({"sort": ["recommended_desc"], "page_size": ["10"]})["items"]
    check(recommended[0]["is_recommended"], "recommended sort mismatch")

    ids = ["photo-demo-001", "photo-demo-002"]
    result = server.payload(f"/api/v1/projects/{server.BATCH_ID}/files/actions", "POST", {}, {"file_ids": ids, "operation": "featured"})
    check(result["succeeded_ids"] == ids, "batch state action failed")
    check(all(server.decisions[item]["keep_state"] == "featured" for item in ids), "batch state was not persisted")

    decision = server.payload(
        f"/api/v1/files/{ids[0]}/decision",
        "POST",
        {},
        {
            "file_id": ids[0],
            "keep_state": "keep",
            "user_species_id": "alcedo-atthis",
            "user_species": "普通翠鸟",
        },
    )
    check(decision["decision"]["user_species_id"] == "alcedo-atthis", "manual species id must round-trip through the decision endpoint")

    server.payload(f"/api/v1/projects/{server.BATCH_ID}/files/actions", "POST", {}, {"file_ids": ids, "operation": "add_tags", "value": ["水鸟"]})
    check(server.read_page({"tags": ["水鸟"], "page_size": ["10"]})["items"], "tag filter failed")
    server.payload(f"/api/v1/projects/{server.BATCH_ID}/files/actions", "POST", {}, {"file_ids": ids, "operation": "remove_tags", "value": ["水鸟"]})
    check(all("水鸟" not in server.decisions[item]["user_tags"] for item in ids), "tag removal failed")

    print("mock box contract checks passed")


if __name__ == "__main__":
    main()
