#!/usr/bin/env ruby
# add_firebase_spm.rb
#
# Safely links FirebaseCore and FirebaseFirestore SPM products to the
# CreditTracker app target by editing project.pbxproj programmatically.
#
# The xcodeproj gem handles UUID generation, section ordering, and
# object-graph consistency — none of which are safe to do by hand at scale.
#
# ONE-TIME SETUP
#   gem install xcodeproj
#
# RUN (from the repo root, with Xcode closed)
#   ruby add_firebase_spm.rb
#
# AFTER RUNNING
#   1. Open CreditTracker.xcodeproj in Xcode.
#   2. Xcode will prompt "The project has package dependencies that are not
#      yet resolved." → click Resolve. It will fetch and pin firebase-ios-sdk.
#   3. Build normally.
#
# NOTE ON FirebaseFirestoreSwift
#   As of Firebase iOS SDK 10.0+, FirebaseFirestoreSwift is NOT a separate
#   SPM product — it was merged into FirebaseFirestore. Attempting to link it
#   as a distinct product causes duplicate-symbol linker errors on SDK 10+.
#   If your Podfile or an older guide references it, ignore that reference.

require 'xcodeproj'

# ── Config ────────────────────────────────────────────────────────────────────
PROJECT_PATH  = File.expand_path('CreditTracker.xcodeproj', __dir__)
APP_TARGET    = 'CreditTracker'
FIREBASE_URL  = 'https://github.com/firebase/firebase-ios-sdk'
FIREBASE_MIN  = '11.0.0'   # bump to the version you want as the lower bound
PRODUCTS      = %w[FirebaseCore FirebaseFirestore]
# ─────────────────────────────────────────────────────────────────────────────

abort "project not found at #{PROJECT_PATH}" unless File.exist?(PROJECT_PATH)

project = Xcodeproj::Project.open(PROJECT_PATH)
target  = project.targets.find { |t| t.name == APP_TARGET }
abort "Target '#{APP_TARGET}' not found in project" unless target

# ── 1. XCRemoteSwiftPackageReference (idempotent) ────────────────────────────
pkg_ref = project.root_object.package_references.find do |r|
  r.respond_to?(:repository_url) && r.repository_url == FIREBASE_URL
end

if pkg_ref
  puts "Package reference already present (#{pkg_ref.uuid}), skipping add."
else
  pkg_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  pkg_ref.repositoryURL = FIREBASE_URL
  pkg_ref.requirement   = {
    kind:           'upToNextMajorVersion',
    minimumVersion: FIREBASE_MIN,
  }
  project.root_object.package_references << pkg_ref
  puts "Added XCRemoteSwiftPackageReference → firebase-ios-sdk >= #{FIREBASE_MIN} (#{pkg_ref.uuid})"
end

# ── 2. XCSwiftPackageProductDependency + PBXBuildFile (idempotent per product) ──
frameworks_phase = target.frameworks_build_phase

PRODUCTS.each do |product_name|
  if target.package_product_dependencies.any? { |d| d.product_name == product_name }
    puts "#{product_name} already linked, skipping."
    next
  end

  # Product dependency object
  dep              = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.package      = pkg_ref
  dep.product_name = product_name
  target.package_product_dependencies << dep

  # Build file that places the product in the Frameworks build phase
  build_file             = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dep
  frameworks_phase.files << build_file

  puts "Linked #{product_name} → target '#{APP_TARGET}' (dep #{dep.uuid}, bf #{build_file.uuid})"
end

# ── 3. Save ──────────────────────────────────────────────────────────────────
project.save
puts "\n✓ project.pbxproj saved. Open Xcode and resolve packages to finish."
