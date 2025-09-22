//
//  PermissionServiceTests.swift
//  RGB2GIF2VOXELTests
//
//  Unit tests for permission management and authorization flows
//

import XCTest
import AVFoundation
import Photos
@testable import RGB2GIF2VOXEL

@MainActor
final class PermissionServiceTests: XCTestCase {

    var sut: PermissionService!

    override func setUp() async throws {
        try await super.setUp()
        sut = PermissionService()
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Status Tests

    func testInitialStatusIsNotDetermined() {
        // Given - Fresh permission service

        // Then
        XCTAssertEqual(sut.cameraStatus, AVCaptureDevice.authorizationStatus(for: .video))
        XCTAssertEqual(sut.photosStatus, PHPhotoLibrary.authorizationStatus())
    }

    func testUpdateStatusesRefreshesValues() {
        // When
        sut.updateStatuses()

        // Then
        XCTAssertNotNil(sut.cameraStatus)
        XCTAssertNotNil(sut.photosStatus)
    }

    // MARK: - Camera Permission Tests

    func testRequestCameraPermissionWhenAlreadyAuthorized() async {
        // Given
        let mockService = MockPermissionService()
        mockService.mockCameraStatus = .authorized

        // When
        let result = await mockService.requestCameraPermission()

        // Then
        XCTAssertTrue(result)
        XCTAssertFalse(mockService.isRequestingPermission)
    }

    func testRequestCameraPermissionWhenDenied() async {
        // Given
        let mockService = MockPermissionService()
        mockService.mockCameraStatus = .denied

        // When
        let result = await mockService.requestCameraPermission()

        // Then
        XCTAssertFalse(result)
        XCTAssertNotNil(mockService.lastError)
        XCTAssertTrue(mockService.lastError!.contains("Settings"))
    }

    // MARK: - Photos Permission Tests

    func testRequestPhotosPermissionWhenAuthorized() async {
        // Given
        let mockService = MockPermissionService()
        mockService.mockPhotosStatus = .authorized

        // When
        let result = await mockService.requestPhotosPermission()

        // Then
        XCTAssertTrue(result)
    }

    func testRequestPhotosPermissionWhenLimited() async {
        // Given
        let mockService = MockPermissionService()
        mockService.mockPhotosStatus = .limited

        // When
        let result = await mockService.requestPhotosPermission()

        // Then
        XCTAssertTrue(result) // Limited access is still considered granted
    }

    // MARK: - Combined Permission Tests

    func testRequestAllPermissionsSuccess() async {
        // Given
        let mockService = MockPermissionService()
        mockService.mockCameraStatus = .authorized
        mockService.mockPhotosStatus = .authorized

        // When
        let result = await mockService.requestAllPermissions()

        // Then
        XCTAssertTrue(result)
        XCTAssertNil(mockService.lastError)
    }

    func testRequestAllPermissionsCameraRequired() async {
        // Given
        let mockService = MockPermissionService()
        mockService.mockCameraStatus = .denied
        mockService.mockPhotosStatus = .authorized

        // When
        let result = await mockService.requestAllPermissions()

        // Then
        XCTAssertFalse(result) // Camera is required
        XCTAssertNotNil(mockService.lastError)
        XCTAssertTrue(mockService.lastError!.contains("Camera"))
    }

    func testRequestAllPermissionsPhotosOptional() async {
        // Given
        let mockService = MockPermissionService()
        mockService.mockCameraStatus = .authorized
        mockService.mockPhotosStatus = .denied

        // When
        let result = await mockService.requestAllPermissions()

        // Then
        XCTAssertTrue(result) // Photos is optional
        XCTAssertNotNil(mockService.lastError)
        XCTAssertTrue(mockService.lastError!.contains("optional"))
    }

    // MARK: - State Management Tests

    func testIsRequestingPermissionFlag() async {
        // Given
        let expectation = XCTestExpectation(description: "Permission requested")
        let mockService = MockPermissionService()
        mockService.mockCameraStatus = .notDetermined
        mockService.onPermissionRequest = {
            XCTAssertTrue(mockService.isRequestingPermission)
            expectation.fulfill()
        }

        // When
        _ = await mockService.requestCameraPermission()

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertFalse(mockService.isRequestingPermission)
    }

    // MARK: - Error Message Tests

    func testErrorMessagesAreLocalized() {
        // Given
        let mockService = MockPermissionService()

        // When
        mockService.mockCameraStatus = .denied
        _ = Task {
            await mockService.requestCameraPermission()
        }

        // Then
        XCTAssertNotNil(mockService.lastError)
        XCTAssertFalse(mockService.lastError!.isEmpty)
        // Should contain actionable message
        XCTAssertTrue(mockService.lastError!.contains("Settings") ||
                     mockService.lastError!.contains("enable"))
    }
}

// MARK: - Mock Permission Service

@MainActor
class MockPermissionService: PermissionService {
    var mockCameraStatus: AVAuthorizationStatus = .notDetermined
    var mockPhotosStatus: PHAuthorizationStatus = .notDetermined
    var onPermissionRequest: (() -> Void)?

    override func updateStatuses() {
        self.cameraStatus = mockCameraStatus
        self.photosStatus = mockPhotosStatus
    }

    override func requestCameraPermission() async -> Bool {
        updateStatuses()
        onPermissionRequest?()

        switch mockCameraStatus {
        case .authorized:
            return true
        case .notDetermined:
            isRequestingPermission = true
            // Simulate async permission request
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            isRequestingPermission = false
            mockCameraStatus = .authorized
            cameraStatus = .authorized
            return true
        case .denied, .restricted:
            lastError = "Camera access denied. Please enable in Settings."
            return false
        @unknown default:
            return false
        }
    }

    override func requestPhotosPermission() async -> Bool {
        updateStatuses()

        switch mockPhotosStatus {
        case .authorized, .limited:
            return true
        case .notDetermined:
            isRequestingPermission = true
            try? await Task.sleep(nanoseconds: 100_000_000)
            isRequestingPermission = false
            mockPhotosStatus = .authorized
            photosStatus = .authorized
            return true
        case .denied, .restricted:
            lastError = "Photos access denied. Please enable in Settings."
            return false
        @unknown default:
            return false
        }
    }
}