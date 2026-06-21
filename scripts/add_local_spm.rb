#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Adds the local iOSExploreServer SPM package to Examples/SPMExample/SPMExample.xcodeproj.
#
# Usage:
#   ruby scripts/add_local_spm.rb
#
# Creates:
#   - XCLocalSwiftPackageReference (relative_path "../../") registered on the project's
#     packageReferences list (root_object.package_references).
#   - XCSwiftPackageProductDependency (product: iOSExploreServer) on the SPMExample target's
#     packageProductDependencies, pointing at the local reference.
#   - PBXBuildFile (product_ref -> product dependency) added to the SPMExample Frameworks
#     build phase so the product is linked.
#
# Idempotent: exits cleanly if the product dependency is already present.

require 'xcodeproj'

REPO_ROOT = File.expand_path('..', __dir__)
PROJ_PATH = File.join(REPO_ROOT, 'Examples', 'SPMExample', 'SPMExample.xcodeproj')

project = Xcodeproj::Project.open(PROJ_PATH)
root = project.root_object

TARGET_NAME  = 'SPMExample'
PRODUCT_NAME = 'iOSExploreServer'
# Relative path from the .xcodeproj to the package root (contains Package.swift).
# SPMExample.xcodeproj is at Examples/SPMExample/, repo root is two levels up.
RELATIVE_PATH = '../../'

Obj = Xcodeproj::Project::Object

target = project.targets.find { |t| t.name == TARGET_NAME }
abort("Target '#{TARGET_NAME}' not found in #{PROJ_PATH}") unless target

# 1. Idempotency: a product dependency of this name already on the target?
if target.package_product_dependencies.any? { |d| d.product_name == PRODUCT_NAME }
  warn "Note: product dependency '#{PRODUCT_NAME}' already on target '#{TARGET_NAME}' — nothing to do."
  exit 0
end

# 2. Create (or reuse) the local package reference on the project's packageReferences list.
local_ref = root.package_references.find do |ref|
  ref.is_a?(Obj::XCLocalSwiftPackageReference) && ref.relative_path == RELATIVE_PATH
end

if local_ref.nil?
  local_ref = project.new(Obj::XCLocalSwiftPackageReference)
  local_ref.relative_path = RELATIVE_PATH
  root.package_references << local_ref
end

# 3. Create the product dependency and attach to the target + local package.
product_dep = project.new(Obj::XCSwiftPackageProductDependency)
product_dep.product_name = PRODUCT_NAME
product_dep.package       = local_ref
target.package_product_dependencies << product_dep

# 4. Add a PBXBuildFile (product_ref -> product dependency) to the Frameworks build phase
#    so the product is actually linked into the app. Xcode does this for app targets.
build_file = project.new(Obj::PBXBuildFile)
build_file.product_ref = product_dep
target.frameworks_build_phase.files << build_file

project.save

puts "Added local SPM package '#{PRODUCT_NAME}' (#{RELATIVE_PATH}) to target '#{TARGET_NAME}'."
