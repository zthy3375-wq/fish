#!/usr/bin/env python3
"""Deterministic, dependency-free Xcode project generator. Run after adding Swift files."""
from pathlib import Path
import hashlib, json
ROOT = Path(__file__).resolve().parents[1]
objects = {}
def uid(value): return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
def add(key_name, isa, **fields):
    key = uid(key_name); objects[key] = dict(isa=isa, **fields); return key
def ref(name): return uid(name)
def config_list(name, settings):
    configs = []
    for variant in ['Debug', 'Release']:
        values = dict(settings)
        values.update(SWIFT_OPTIMIZATION_LEVEL='-Onone' if variant == 'Debug' else '-O', DEBUG_INFORMATION_FORMAT='dwarf' if variant == 'Debug' else 'dwarf-with-dsym')
        if variant == 'Debug': values['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
        configs.append(add(name+variant, 'XCBuildConfiguration', buildSettings=values, name=variant))
    return add(name+'configs', 'XCConfigurationList', buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName='Release')
shared_files = sorted((ROOT/'Shared').glob('*.swift'))
app_files = sorted((ROOT/'Hanyuantong').rglob('*.swift')) + shared_files
widget_files = sorted((ROOT/'Widget').glob('*.swift')) + shared_files
unit_files = sorted((ROOT/'Tests').glob('*.swift'))
ui_files = sorted((ROOT/'UITests').glob('*.swift'))
resources = [ROOT/'Hanyuantong/Assets.xcassets'] + sorted((ROOT/'Hanyuantong/Resources').glob('*'))
groups = []
for title, files in [('Sources',app_files),('Tests',unit_files),('UITests',ui_files),('Resources', resources),('Widget', [x for x in widget_files if x not in shared_files])]:
    entries=[]
    for file in files:
        path=file.relative_to(ROOT).as_posix()
        kind='sourcecode.swift' if file.suffix=='.swift' else 'folder.assetcatalog' if file.suffix=='.xcassets' else 'text.xml' if file.suffix=='.xcprivacy' else 'sourcecode.javascript'
        entries.append(add(path,'PBXFileReference',lastKnownFileType=kind,path=path,sourceTree='<group>'))
        add('build:'+path,'PBXBuildFile',fileRef=ref(path))
    groups.append(add(title,'PBXGroup',children=entries,name=title,sourceTree='<group>'))
products=[]; targets=[]
base=dict(SWIFT_VERSION='5.0', IPHONEOS_DEPLOYMENT_TARGET='16.0', SDKROOT='iphoneos', TARGETED_DEVICE_FAMILY='1', CODE_SIGN_STYLE='Automatic', DEVELOPMENT_TEAM='', ENABLE_USER_SCRIPT_SANDBOXING='YES', CLANG_ENABLE_MODULES='YES')
for name,files,extension,ptype in [('Hanyuantong',app_files,'app','application'),('HanyuantongWidget',widget_files,'appex','app-extension'),('HanyuantongTests',unit_files,'xctest','bundle.unit-test'),('HanyuantongUITests',ui_files,'xctest','bundle.ui-testing')]:
    product=add(name+'product','PBXFileReference',explicitFileType='wrapper.application' if extension=='app' else 'wrapper.app-extension' if extension=='appex' else 'wrapper.cfbundle',includeInIndex=0,path=name+'.'+extension,sourceTree='BUILT_PRODUCTS_DIR');products.append(product)
    sources=add(name+'sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=[ref('build:'+x.relative_to(ROOT).as_posix()) for x in files],runOnlyForDeploymentPostprocessing=0)
    frameworks=add(name+'frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
    resource=add(name+'resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=[ref('build:'+x.relative_to(ROOT).as_posix()) for x in resources] if extension=='app' else [],runOnlyForDeploymentPostprocessing=0)
    settings=dict(base,PRODUCT_NAME='$(TARGET_NAME)',PRODUCT_BUNDLE_IDENTIFIER='org.handancampus.ios.native'+('' if extension=='app' else '.'+name),SUPPORTED_PLATFORMS='iphoneos iphonesimulator',ENABLE_TESTABILITY='YES',GENERATE_INFOPLIST_FILE='YES',LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/Frameworks'])
    deps=[]; phases=[sources,frameworks,resource]
    if extension=='app':settings.update(GENERATE_INFOPLIST_FILE='NO',INFOPLIST_FILE='Hanyuantong/Info.plist',ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon',ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME='',SUPPORTS_MACCATALYST='NO',CODE_SIGN_ENTITLEMENTS='Hanyuantong/Hanyuantong.entitlements',OTHER_LDFLAGS=['$(inherited)','-lz'])
    elif extension=='appex':
        settings.update(GENERATE_INFOPLIST_FILE='NO',INFOPLIST_FILE='Widget/Info.plist',CODE_SIGN_ENTITLEMENTS='Widget/Widget.entitlements',APPLICATION_EXTENSION_API_ONLY='YES',SKIP_INSTALL='YES',LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/Frameworks','@executable_path/../../Frameworks'])
    else:
        if name=='HanyuantongTests':settings.update(TEST_HOST='$(BUILT_PRODUCTS_DIR)/Hanyuantong.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Hanyuantong',BUNDLE_LOADER='$(TEST_HOST)')
        else:settings.update(TEST_TARGET_NAME='Hanyuantong')
        proxy=add(name+'proxy','PBXContainerItemProxy',containerPortal=ref('project'),proxyType=1,remoteGlobalIDString=ref('Hanyuantongtarget'),remoteInfo='Hanyuantong')
        deps=[add(name+'dependency','PBXTargetDependency',target=ref('Hanyuantongtarget'),targetProxy=proxy)]
    if extension=='app':
        proxy=add('widgetproxy','PBXContainerItemProxy',containerPortal=ref('project'),proxyType=1,remoteGlobalIDString=ref('HanyuantongWidgettarget'),remoteInfo='HanyuantongWidget')
        deps.append(add('widgetdependency','PBXTargetDependency',target=ref('HanyuantongWidgettarget'),targetProxy=proxy))
        embed=add('widgetembed','PBXBuildFile',fileRef=ref('HanyuantongWidgetproduct'),settings={'ATTRIBUTES':['RemoveHeadersOnCopy','CodeSignOnCopy']})
        phases.append(add('embedextensions','PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=13,files=[embed],name='Embed App Extensions',runOnlyForDeploymentPostprocessing=0))
    targets.append(add(name+'target','PBXNativeTarget',buildConfigurationList=config_list(name,settings),buildPhases=phases,buildRules=[],dependencies=deps,name=name,productName=name,productReference=product,productType='com.apple.product-type.'+ptype))
products_group=add('Products','PBXGroup',children=products,name='Products',sourceTree='<group>')
main=add('main','PBXGroup',children=groups+[products_group],sourceTree='<group>')
add('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'1600'},buildConfigurationList=config_list('project',dict(base,CLANG_WARN_DOCUMENTATION_COMMENTS='YES',SWIFT_STRICT_CONCURRENCY='targeted')),compatibilityVersion='Xcode 14.0',developmentRegion='zh_CN',hasScannedForEncodings=0,knownRegions=['zh_CN','en','Base'],mainGroup=main,productRefGroup=products_group,projectDirPath='',projectRoot='',targets=targets)
def value(v,level=0):
    if isinstance(v,dict):return '{\n'+''.join('\t'*(level+1)+json.dumps(k)+ ' = '+value(x,level+1)+';\n' for k,x in v.items())+'\t'*level+'}'
    if isinstance(v,list):return '( '+', '.join(value(x,level+1) for x in v)+' )'
    if isinstance(v,int):return str(v)
    return json.dumps(v,ensure_ascii=False)
project=ROOT/'Hanyuantong.xcodeproj';project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n'+value({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':ref('project')})+'\n')
scheme=project/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
def buildable(name):return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref(name+"target")}" BuildableName="{name}.{"app" if name=="Hanyuantong" else "xctest"}" BlueprintName="{name}" ReferencedContainer="container:Hanyuantong.xcodeproj"/>'
(scheme/'Hanyuantong.xcscheme').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">'+buildable('Hanyuantong')+'</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>'+''.join('<TestableReference skipped="NO">'+buildable(n)+'</TestableReference>' for n in ['HanyuantongTests','HanyuantongUITests'])+'</Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">'+buildable('Hanyuantong')+'</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>\n')
print('Generated project:',len(app_files),'app Swift files,',len(unit_files),'unit tests,',len(ui_files),'UI tests')
