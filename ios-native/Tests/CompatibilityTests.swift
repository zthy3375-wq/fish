import XCTest
import UIKit
import UniformTypeIdentifiers
@testable import Hanyuantong

final class CompatibilityTests: XCTestCase {
    func testBoundedPhotoReadRejectsSizeBeforeDecoding() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(repeating: 1, count: 21).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.image.identifier, fileOptions: [], visibility: .all) { completion in
            completion(file, false, nil)
            return nil
        }
        let accepted = try await CampusPhotoItem(provider: provider).loadBoundedData(maximumBytes: 21)
        XCTAssertEqual(accepted.count, 21)
        do {
            _ = try await CampusPhotoItem(provider: provider).loadBoundedData(maximumBytes: 20)
            XCTFail("Oversized photo must be rejected before decoding")
        } catch { XCTAssertEqual((error as NSError).code, CocoaError.Code.fileReadTooLarge.rawValue) }
    }
    func testPhotoSelectionIdentityDoesNotReuseAnotherSelection() {
        let provider = NSItemProvider()
        let item = CampusPhotoItem(provider: provider)
        XCTAssertEqual(item, item)
        XCTAssertNotEqual(item, CampusPhotoItem(provider: provider))
    }
    func testPickerLoadsSelectedBytesForExistingImageValidation() async throws {
        let bytes = Data([1, 2, 3, 4])
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.image.identifier, visibility: .all) { completion in
            completion(bytes, nil)
            return nil
        }
        let loaded = try await CampusPhotoItem(provider: provider).loadData()
        XCTAssertEqual(loaded, bytes)
    }
    func testPickerReadFailureDoesNotBecomeAnEmptySuccessfulImage() async {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.image.identifier, visibility: .all) { completion in
            completion(nil, CocoaError(.fileReadNoPermission))
            return nil
        }
        do {
            _ = try await CampusPhotoItem(provider: provider).loadData()
            XCTFail("Photo read errors must reach the existing draft error handling")
        } catch { XCTAssertNotNil(error) }
    }
}
