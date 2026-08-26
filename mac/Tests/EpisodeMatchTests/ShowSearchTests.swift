import XCTest
@testable import EpisodeMatch

struct FakeShow: ShowSearchable {
    let name: String
    let alias: String
    let location: String
    let genres: [String]
    let description: String

    init(name: String, alias: String, location: String = "", genres: [String] = [],
         description: String = "") {
        self.name = name
        self.alias = alias
        self.location = location
        self.genres = genres
        self.description = description
    }

    var haystack: String {
        ShowSearch.haystack(name: name, alias: alias, location: location,
                            genres: genres, description: description)
    }
}

final class ShowSearchTests: XCTestCase {
    /// The show the whole feature was built for: real name from
    /// `/api/v2/shows/pussyrap`, host blurb from its `description`.
    let pussyrap = FakeShow(
        name: "PU$$YRAP W/ JODY SIMMS",
        alias: "pussyrap",
        location: "TEX",
        description: "Jody Simms aka DJ Jody aka CreoleMami hosts Pu$$yRap centering women of color in music."
    )
    let unrelated = FakeShow(name: "Lung Dart", alias: "lung-dart", location: "LDN")

    func testFold() {
        XCTAssertEqual(ShowSearch.fold("PU$$YRAP W/ JODY SIMMS"), "puyrap w jody simms")
    }

    /// Case 4 from the brief: "jody simm" must find the show, and it must
    /// rank ahead of an unrelated show.
    func testSearchByHostNameFindsAndRanksTheShowFirst() {
        let shows = [unrelated, pussyrap]
        let hits = shows
            .filter { ShowSearch.matches(query: "jody simm", haystack: $0.haystack) }
            .sorted { ShowSearch.rank(query: "jody simm", $0) < ShowSearch.rank(query: "jody simm", $1) }
        XCTAssertEqual(hits.first?.alias, "pussyrap")
    }

    /// Case 5, the required folding regression: once the alias-derived name
    /// is replaced by the real, punctuation-heavy name, the alias itself
    /// must still be findable — the alias is in the haystack precisely so
    /// folding it can't break this.
    func testAliasStaysSearchableAfterRealNameReplacesIt() {
        XCTAssertTrue(ShowSearch.matches(query: "pussyrap", haystack: pussyrap.haystack))
        XCTAssertEqual(ShowSearch.rank(query: "pussyrap", pussyrap), 2, "alias-tier match")
    }

    /// Case 6: a query that only appears in the description still hits.
    func testMatchesViaDescriptionOnly() {
        XCTAssertTrue(ShowSearch.matches(query: "creolemami", haystack: pussyrap.haystack))
        XCTAssertFalse(ShowSearch.matches(query: "creolemami", haystack: unrelated.haystack))
        XCTAssertEqual(ShowSearch.rank(query: "creolemami", pussyrap), 4, "description-only tier")
    }

    func testEveryQueryTokenMustMatch() {
        XCTAssertFalse(ShowSearch.matches(query: "jody nobody", haystack: pussyrap.haystack))
    }
}
