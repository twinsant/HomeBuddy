//
//  HomeBuddyTests.swift
//  HomeBuddyTests
//
//  Created by Atman An on 2026/8/26.
//

import AppKit
import Testing
@testable import HomeBuddy

@MainActor
struct HomeBuddyTests {

    @Test func horizontalSwipeNavigatesOnceWithoutMomentum() {
        var state = PhotoViewerScrollState()
        #expect(state.handle(delta: CGSize(width: 20, height: 1), phase: .began,
                             momentumPhase: [], isZoomed: false) == .none)
        #expect(state.handle(delta: CGSize(width: 25, height: 1), phase: .changed,
                             momentumPhase: [], isZoomed: false) == .navigate(45))
        #expect(state.handle(delta: CGSize(width: 80, height: 0), phase: .changed,
                             momentumPhase: [], isZoomed: false) == .none)
        #expect(state.handle(delta: .zero, phase: .ended,
                             momentumPhase: [], isZoomed: false) == .none)
        #expect(state.handle(delta: CGSize(width: 80, height: 0), phase: [],
                             momentumPhase: .began, isZoomed: false) == .none)
        #expect(state.handle(delta: CGSize(width: -45, height: 0), phase: .began,
                             momentumPhase: [], isZoomed: false) == .navigate(-45))
    }

    @Test func verticalSwipeAndSmallSwipeDoNotNavigate() {
        var state = PhotoViewerScrollState()
        #expect(state.handle(delta: CGSize(width: 45, height: 90), phase: .began,
                             momentumPhase: [], isZoomed: false) == .none)
        #expect(state.handle(delta: CGSize(width: 10, height: 0), phase: .began,
                             momentumPhase: [], isZoomed: false) == .none)
        #expect(state.handle(delta: .zero, phase: .ended,
                             momentumPhase: [], isZoomed: false) == .none)
        #expect(state.handle(delta: CGSize(width: 80, height: 0), phase: [],
                             momentumPhase: .changed, isZoomed: false) == .none)
    }

    @Test func zoomedSwipePansBothAxesIncludingMomentum() {
        var state = PhotoViewerScrollState()
        let delta = CGSize(width: 60, height: -80)
        #expect(state.handle(delta: delta, phase: .began,
                             momentumPhase: [], isZoomed: true) == .pan(delta))
        let reverse = CGSize(width: -20, height: 30)
        #expect(state.handle(delta: reverse, phase: .changed,
                             momentumPhase: [], isZoomed: true) == .pan(reverse))
        #expect(state.handle(delta: delta, phase: [],
                             momentumPhase: .changed, isZoomed: true) == .pan(delta))
    }

    @Test func zoomResetDuringPanDoesNotSwitchPhotos() {
        var state = PhotoViewerScrollState()
        let delta = CGSize(width: 60, height: 0)
        #expect(state.handle(delta: delta, phase: .began,
                             momentumPhase: [], isZoomed: true) == .pan(delta))
        #expect(state.handle(delta: delta, phase: .changed,
                             momentumPhase: [], isZoomed: false) == .none)
        #expect(state.handle(delta: delta, phase: [],
                             momentumPhase: .changed, isZoomed: false) == .none)
        #expect(state.handle(delta: delta, phase: .began,
                             momentumPhase: [], isZoomed: false) == .navigate(60))
    }

    @Test func cancelledSwipeDoesNotLeakIntoNextGesture() {
        var state = PhotoViewerScrollState()
        _ = state.handle(delta: CGSize(width: 30, height: 0), phase: .began,
                         momentumPhase: [], isZoomed: false)
        #expect(state.handle(delta: .zero, phase: .cancelled,
                             momentumPhase: [], isZoomed: false) == .none)
        #expect(state.handle(delta: CGSize(width: 20, height: 0), phase: .began,
                             momentumPhase: [], isZoomed: false) == .none)
    }

    @Test func panBoundsFollowZoomAndViewport() {
        let image = CGSize(width: 1000, height: 1000)
        let viewport = CGSize(width: 548, height: 548)
        let offset = CGSize(width: 1000, height: -1000)
        #expect(PhotoViewerGeometry.boundedOffset(offset, imageSize: image,
                    viewportSize: viewport, zoomScale: 2) == CGSize(width: 226, height: -226))
        #expect(PhotoViewerGeometry.boundedOffset(offset, imageSize: image,
                    viewportSize: viewport, zoomScale: 1) == .zero)
        #expect(PhotoViewerGeometry.boundedOffset(offset, imageSize: image,
                    viewportSize: CGSize(width: 348, height: 348), zoomScale: 2)
                == CGSize(width: 126, height: -126))
    }

    @Test func smallerImageAxisStaysCentered() {
        let offset = CGSize(width: 1000, height: -1000)
        let viewport = CGSize(width: 548, height: 548)
        #expect(PhotoViewerGeometry.boundedOffset(offset,
                    imageSize: CGSize(width: 1000, height: 100), viewportSize: viewport,
                    zoomScale: 2) == CGSize(width: 226, height: 0))
        #expect(PhotoViewerGeometry.boundedOffset(offset,
                    imageSize: CGSize(width: 100, height: 1000), viewportSize: viewport,
                    zoomScale: 2) == CGSize(width: 0, height: -226))
        #expect(PhotoViewerGeometry.boundedOffset(offset, imageSize: .zero,
                    viewportSize: viewport, zoomScale: 2) == .zero)
    }

}
