#!/usr/bin/env python3
import os
import uuid

def gen_id():
    return uuid.uuid4().hex[:24].upper()

def main():
    proj_dir = "VeraFlow.xcodeproj"
    os.makedirs(proj_dir, exist_ok=True)
    os.makedirs(f"{proj_dir}/xcshareddata/xcschemes", exist_ok=True)
    
    # Collect swift files
    app_files = []
    for root, _, files in os.walk("VeraFlow"):
        for f in files:
            if f.endswith(".swift"):
                rel_path = os.path.relpath(os.path.join(root, f), ".")
                app_files.append((f, rel_path))
                
    test_files = []
    for root, _, files in os.walk("VeraFlowTests"):
        for f in files:
            if f.endswith(".swift"):
                rel_path = os.path.relpath(os.path.join(root, f), ".")
                test_files.append((f, rel_path))

    # Generate IDs
    proj_id = gen_id()
    main_group_id = gen_id()
    app_group_id = gen_id()
    tests_group_id = gen_id()
    products_group_id = gen_id()
    
    app_target_id = gen_id()
    tests_target_id = gen_id()
    
    app_product_id = gen_id()
    tests_product_id = gen_id()
    
    app_sources_id = gen_id()
    tests_sources_id = gen_id()
    
    app_frameworks_id = gen_id()
    tests_frameworks_id = gen_id()
    
    app_config_list_id = gen_id()
    tests_config_list_id = gen_id()
    proj_config_list_id = gen_id()
    
    proj_debug_config_id = gen_id()
    proj_release_config_id = gen_id()
    app_debug_config_id = gen_id()
    app_release_config_id = gen_id()
    tests_debug_config_id = gen_id()
    tests_release_config_id = gen_id()
    
    # Build file refs
    file_refs = {}
    build_files = {}
    
    for name, path in app_files:
        fid = gen_id()
        bid = gen_id()
        file_refs[path] = (fid, name, path)
        build_files[path] = (bid, fid, name)
        
    for name, path in test_files:
        fid = gen_id()
        bid = gen_id()
        file_refs[path] = (fid, name, path)
        build_files[path] = (bid, fid, name)

    pbx = []
    pbx.append("// !$*UTF8*$!")
    pbx.append("{")
    pbx.append("\tarchiveVersion = 1;")
    pbx.append("\tclasses = {")
    pbx.append("\t};")
    pbx.append("\tobjectVersion = 60;")
    pbx.append("\tobjects = {")
    
    # PBXBuildFile
    pbx.append("/* Begin PBXBuildFile section */")
    for path, (bid, fid, name) in build_files.items():
        pbx.append(f"\t\t{bid} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {name} */; }};")
    pbx.append("/* End PBXBuildFile section */")
    
    # PBXFileReference
    pbx.append("/* Begin PBXFileReference section */")
    pbx.append(f"\t\t{app_product_id} /* VeraFlow.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = VeraFlow.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    pbx.append(f"\t\t{tests_product_id} /* VeraFlowTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = VeraFlowTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
    for path, (fid, name, p) in file_refs.items():
        pbx.append(f"\t\t{fid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = \"{name}\"; path = \"{p}\"; sourceTree = \"<group>\"; }};")
    pbx.append("/* End PBXFileReference section */")
    
    # PBXFrameworksBuildPhase
    pbx.append("/* Begin PBXFrameworksBuildPhase section */")
    pbx.append(f"\t\t{app_frameworks_id} /* Frameworks */ = {{")
    pbx.append("\t\t\tisa = PBXFrameworksBuildPhase;")
    pbx.append("\t\t\tbuildActionMask = 2147483647;")
    pbx.append("\t\t\tfiles = (")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    pbx.append("\t\t};")
    pbx.append(f"\t\t{tests_frameworks_id} /* Frameworks */ = {{")
    pbx.append("\t\t\tisa = PBXFrameworksBuildPhase;")
    pbx.append("\t\t\tbuildActionMask = 2147483647;")
    pbx.append("\t\t\tfiles = (")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    pbx.append("\t\t};")
    pbx.append("/* End PBXFrameworksBuildPhase section */")
    
    # PBXGroup
    pbx.append("/* Begin PBXGroup section */")
    pbx.append(f"\t\t{main_group_id} = {{")
    pbx.append("\t\t\tisa = PBXGroup;")
    pbx.append("\t\t\tchildren = (")
    pbx.append(f"\t\t\t\t{app_group_id} /* VeraFlow */,")
    pbx.append(f"\t\t\t\t{tests_group_id} /* VeraFlowTests */,")
    pbx.append(f"\t\t\t\t{products_group_id} /* Products */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tsourceTree = \"<group>\";")
    pbx.append("\t\t};")
    
    # App Group
    pbx.append(f"\t\t{app_group_id} /* VeraFlow */ = {{")
    pbx.append("\t\t\tisa = PBXGroup;")
    pbx.append("\t\t\tchildren = (")
    for path, (fid, name, _) in file_refs.items():
        if path.startswith("VeraFlow/"):
            pbx.append(f"\t\t\t\t{fid} /* {name} */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tpath = VeraFlow;")
    pbx.append("\t\t\tsourceTree = \"<group>\";")
    pbx.append("\t\t};")
    
    # Tests Group
    pbx.append(f"\t\t{tests_group_id} /* VeraFlowTests */ = {{")
    pbx.append("\t\t\tisa = PBXGroup;")
    pbx.append("\t\t\tchildren = (")
    for path, (fid, name, _) in file_refs.items():
        if path.startswith("VeraFlowTests/"):
            pbx.append(f"\t\t\t\t{fid} /* {name} */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tpath = VeraFlowTests;")
    pbx.append("\t\t\tsourceTree = \"<group>\";")
    pbx.append("\t\t};")
    
    # Products Group
    pbx.append(f"\t\t{products_group_id} /* Products */ = {{")
    pbx.append("\t\t\tisa = PBXGroup;")
    pbx.append("\t\t\tchildren = (")
    pbx.append(f"\t\t\t\t{app_product_id} /* VeraFlow.app */,")
    pbx.append(f"\t\t\t\t{tests_product_id} /* VeraFlowTests.xctest */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tname = Products;")
    pbx.append("\t\t\tsourceTree = \"<group>\";")
    pbx.append("\t\t};")
    pbx.append("/* End PBXGroup section */")
    
    # PBXNativeTarget
    pbx.append("/* Begin PBXNativeTarget section */")
    # App Target
    pbx.append(f"\t\t{app_target_id} /* VeraFlow */ = {{")
    pbx.append("\t\t\tisa = PBXNativeTarget;")
    pbx.append(f"\t\t\tbuildConfigurationList = {app_config_list_id} /* Build configuration list for PBXNativeTarget \"VeraFlow\" */;")
    pbx.append("\t\t\tbuildPhases = (")
    pbx.append(f"\t\t\t\t{app_sources_id} /* Sources */,")
    pbx.append(f"\t\t\t\t{app_frameworks_id} /* Frameworks */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tbuildRules = (")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tdependencies = (")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tname = VeraFlow;")
    pbx.append("\t\t\tproductName = VeraFlow;")
    pbx.append(f"\t\t\tproductReference = {app_product_id} /* VeraFlow.app */;")
    pbx.append("\t\t\tproductType = \"com.apple.product-type.application\";")
    pbx.append("\t\t};")
    
    # Tests Target
    pbx.append(f"\t\t{tests_target_id} /* VeraFlowTests */ = {{")
    pbx.append("\t\t\tisa = PBXNativeTarget;")
    pbx.append(f"\t\t\tbuildConfigurationList = {tests_config_list_id} /* Build configuration list for PBXNativeTarget \"VeraFlowTests\" */;")
    pbx.append("\t\t\tbuildPhases = (")
    pbx.append(f"\t\t\t\t{tests_sources_id} /* Sources */,")
    pbx.append(f"\t\t\t\t{tests_frameworks_id} /* Frameworks */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tbuildRules = (")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tdependencies = (")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tname = VeraFlowTests;")
    pbx.append("\t\t\tproductName = VeraFlowTests;")
    pbx.append(f"\t\t\tproductReference = {tests_product_id} /* VeraFlowTests.xctest */;")
    pbx.append("\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";")
    pbx.append("\t\t};")
    pbx.append("/* End PBXNativeTarget section */")
    
    # PBXProject
    pbx.append("/* Begin PBXProject section */")
    pbx.append(f"\t\t{proj_id} /* Project object */ = {{")
    pbx.append("\t\t\tisa = PBXProject;")
    pbx.append("\t\t\tattributes = {")
    pbx.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    pbx.append("\t\t\t\tLastUpgradeCheck = 1600;")
    pbx.append("\t\t\t};")
    pbx.append(f"\t\t\tbuildConfigurationList = {proj_config_list_id} /* Build configuration list for PBXProject \"VeraFlow\" */;")
    pbx.append("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    pbx.append("\t\t\tdevelopmentRegion = en;")
    pbx.append("\t\t\thasScannedForEncodings = 0;")
    pbx.append("\t\t\tknownRegions = (")
    pbx.append("\t\t\t\ten,")
    pbx.append("\t\t\t\tBase,")
    pbx.append("\t\t\t);")
    pbx.append(f"\t\t\tmainGroup = {main_group_id};")
    pbx.append(f"\t\t\tproductRefGroup = {products_group_id} /* Products */;")
    pbx.append("\t\t\tprojectDirPath = \"\";")
    pbx.append("\t\t\tprojectRoot = \"\";")
    pbx.append("\t\t\ttargets = (")
    pbx.append(f"\t\t\t\t{app_target_id} /* VeraFlow */,")
    pbx.append(f"\t\t\t\t{tests_target_id} /* VeraFlowTests */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t};")
    pbx.append("/* End PBXProject section */")
    
    # PBXSourcesBuildPhase
    pbx.append("/* Begin PBXSourcesBuildPhase section */")
    pbx.append(f"\t\t{app_sources_id} /* Sources */ = {{")
    pbx.append("\t\t\tisa = PBXSourcesBuildPhase;")
    pbx.append("\t\t\tbuildActionMask = 2147483647;")
    pbx.append("\t\t\tfiles = (")
    for path, (bid, fid, name) in build_files.items():
        if path.startswith("VeraFlow/"):
            pbx.append(f"\t\t\t\t{bid} /* {name} in Sources */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    pbx.append("\t\t};")
    
    pbx.append(f"\t\t{tests_sources_id} /* Sources */ = {{")
    pbx.append("\t\t\tisa = PBXSourcesBuildPhase;")
    pbx.append("\t\t\tbuildActionMask = 2147483647;")
    pbx.append("\t\t\tfiles = (")
    for path, (bid, fid, name) in build_files.items():
        if path.startswith("VeraFlowTests/"):
            pbx.append(f"\t\t\t\t{bid} /* {name} in Sources */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    pbx.append("\t\t};")
    pbx.append("/* End PBXSourcesBuildPhase section */")
    
    # XCBuildConfiguration
    pbx.append("/* Begin XCBuildConfiguration section */")
    # Project Debug
    pbx.append(f"\t\t{proj_debug_config_id} /* Debug */ = {{")
    pbx.append("\t\t\tisa = XCBuildConfiguration;")
    pbx.append("\t\t\tbuildSettings = {")
    pbx.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    pbx.append("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    pbx.append("\t\t\t\tENABLE_TESTABILITY = YES;")
    pbx.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 26.0;")
    pbx.append("\t\t\t\tSDKROOT = iphoneos;")
    pbx.append("\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;")
    pbx.append("\t\t\t\tSWIFT_VERSION = 6.0;")
    pbx.append("\t\t\t};")
    pbx.append("\t\t\tname = Debug;")
    pbx.append("\t\t};")
    
    # Project Release
    pbx.append(f"\t\t{proj_release_config_id} /* Release */ = {{")
    pbx.append("\t\t\tisa = XCBuildConfiguration;")
    pbx.append("\t\t\tbuildSettings = {")
    pbx.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    pbx.append("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    pbx.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 26.0;")
    pbx.append("\t\t\t\tSDKROOT = iphoneos;")
    pbx.append("\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;")
    pbx.append("\t\t\t\tSWIFT_VERSION = 6.0;")
    pbx.append("\t\t\t};")
    pbx.append("\t\t\tname = Release;")
    pbx.append("\t\t};")
    
    # App Debug
    pbx.append(f"\t\t{app_debug_config_id} /* Debug */ = {{")
    pbx.append("\t\t\tisa = XCBuildConfiguration;")
    pbx.append("\t\t\tbuildSettings = {")
    pbx.append("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
    pbx.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    pbx.append("\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
    pbx.append("\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = VeraFlow;")
    pbx.append("\t\t\t\tINFOPLIST_KEY_NSMicrophoneUsageDescription = \"VeraFlow records meetings and audio locally on your iPhone. Audio never leaves your device.\";")
    pbx.append("\t\t\t\tINFOPLIST_KEY_UIBackgroundModes = audio;")
    pbx.append("\t\t\t\tMARKETING_VERSION = 1.0;")
    pbx.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.veraflow.app;")
    pbx.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    pbx.append("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
    pbx.append("\t\t\t};")
    pbx.append("\t\t\tname = Debug;")
    pbx.append("\t\t};")
    
    # App Release
    pbx.append(f"\t\t{app_release_config_id} /* Release */ = {{")
    pbx.append("\t\t\tisa = XCBuildConfiguration;")
    pbx.append("\t\t\tbuildSettings = {")
    pbx.append("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
    pbx.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    pbx.append("\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
    pbx.append("\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = VeraFlow;")
    pbx.append("\t\t\t\tINFOPLIST_KEY_NSMicrophoneUsageDescription = \"VeraFlow records meetings and audio locally on your iPhone. Audio never leaves your device.\";")
    pbx.append("\t\t\t\tINFOPLIST_KEY_UIBackgroundModes = audio;")
    pbx.append("\t\t\t\tMARKETING_VERSION = 1.0;")
    pbx.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.veraflow.app;")
    pbx.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    pbx.append("\t\t\t};")
    pbx.append("\t\t\tname = Release;")
    pbx.append("\t\t};")
    
    # Tests Debug
    pbx.append(f"\t\t{tests_debug_config_id} /* Debug */ = {{")
    pbx.append("\t\t\tisa = XCBuildConfiguration;")
    pbx.append("\t\t\tbuildSettings = {")
    pbx.append("\t\t\t\tBUNDLE_LOADER = \"$(TEST_HOST)\";")
    pbx.append("\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
    pbx.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.veraflow.VeraFlowTests;")
    pbx.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    pbx.append(f"\t\t\t\tTEST_HOST = \"$(BUILT_PRODUCTS_DIR)/VeraFlow.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/VeraFlow\";")
    pbx.append("\t\t\t};")
    pbx.append("\t\t\tname = Debug;")
    pbx.append("\t\t};")
    
    # Tests Release
    pbx.append(f"\t\t{tests_release_config_id} /* Release */ = {{")
    pbx.append("\t\t\tisa = XCBuildConfiguration;")
    pbx.append("\t\t\tbuildSettings = {")
    pbx.append("\t\t\t\tBUNDLE_LOADER = \"$(TEST_HOST)\";")
    pbx.append("\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
    pbx.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.veraflow.VeraFlowTests;")
    pbx.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    pbx.append(f"\t\t\t\tTEST_HOST = \"$(BUILT_PRODUCTS_DIR)/VeraFlow.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/VeraFlow\";")
    pbx.append("\t\t\t};")
    pbx.append("\t\t\tname = Release;")
    pbx.append("\t\t};")
    pbx.append("/* End XCBuildConfiguration section */")
    
    # XCConfigurationList
    pbx.append("/* Begin XCConfigurationList section */")
    pbx.append(f"\t\t{proj_config_list_id} /* Build configuration list for PBXProject \"VeraFlow\" */ = {{")
    pbx.append("\t\t\tisa = XCConfigurationList;")
    pbx.append("\t\t\tbuildConfigurations = (")
    pbx.append(f"\t\t\t\t{proj_debug_config_id} /* Debug */,")
    pbx.append(f"\t\t\t\t{proj_release_config_id} /* Release */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    pbx.append("\t\t\tdefaultConfigurationName = Release;")
    pbx.append("\t\t};")
    
    pbx.append(f"\t\t{app_config_list_id} /* Build configuration list for PBXNativeTarget \"VeraFlow\" */ = {{")
    pbx.append("\t\t\tisa = XCConfigurationList;")
    pbx.append("\t\t\tbuildConfigurations = (")
    pbx.append(f"\t\t\t\t{app_debug_config_id} /* Debug */,")
    pbx.append(f"\t\t\t\t{app_release_config_id} /* Release */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    pbx.append("\t\t\tdefaultConfigurationName = Release;")
    pbx.append("\t\t};")
    
    pbx.append(f"\t\t{tests_config_list_id} /* Build configuration list for PBXNativeTarget \"VeraFlowTests\" */ = {{")
    pbx.append("\t\t\tisa = XCConfigurationList;")
    pbx.append("\t\t\tbuildConfigurations = (")
    pbx.append(f"\t\t\t\t{tests_debug_config_id} /* Debug */,")
    pbx.append(f"\t\t\t\t{tests_release_config_id} /* Release */,")
    pbx.append("\t\t\t);")
    pbx.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    pbx.append("\t\t\tdefaultConfigurationName = Release;")
    pbx.append("\t\t};")
    pbx.append("/* End XCConfigurationList section */")
    
    pbx.append("\t};")
    pbx.append(f"\trootObject = {proj_id} /* Project object */;")
    pbx.append("}")
    
    with open(f"{proj_dir}/project.pbxproj", "w") as f:
        f.write("\n".join(pbx) + "\n")
    print("Generated VeraFlow.xcodeproj/project.pbxproj successfully!")

if __name__ == "__main__":
    main()
