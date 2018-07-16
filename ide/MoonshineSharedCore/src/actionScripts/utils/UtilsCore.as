﻿////////////////////////////////////////////////////////////////////////////////
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
// http://www.apache.org/licenses/LICENSE-2.0 
// 
// Unless required by applicable law or agreed to in writing, software 
// distributed under the License is distributed on an "AS IS" BASIS, 
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and 
// limitations under the License
// 
// No warranty of merchantability or fitness of any kind. 
// Use this software at your own risk.
// 
////////////////////////////////////////////////////////////////////////////////
package actionScripts.utils
{
	import flash.display.DisplayObject;
	import flash.geom.Point;
	import flash.system.Capabilities;
	
	import mx.collections.ArrayCollection;
	import mx.collections.ICollectionView;
	import mx.collections.IList;
	import mx.core.FlexGlobals;
	import mx.core.UIComponent;
	import mx.events.CloseEvent;
	import mx.events.ToolTipEvent;
	import mx.managers.PopUpManager;
	import mx.resources.ResourceManager;
	import mx.utils.UIDUtil;
	
	import actionScripts.events.GlobalEventDispatcher;
	import actionScripts.events.ProjectEvent;
	import actionScripts.factory.FileLocation;
	import actionScripts.locator.IDEModel;
	import actionScripts.plugin.actionscript.as3project.vo.AS3ProjectVO;
	import actionScripts.plugin.actionscript.as3project.vo.SWFOutputVO;
	import actionScripts.plugin.settings.SettingsView;
	import actionScripts.ui.IContentWindow;
	import actionScripts.ui.editor.BasicTextEditor;
	import actionScripts.ui.menu.vo.MenuItem;
	import actionScripts.ui.menu.vo.ProjectMenuTypes;
	import actionScripts.ui.tabview.CloseTabEvent;
	import actionScripts.valueObjects.ConstantsCoreVO;
	import actionScripts.valueObjects.DataHTMLType;
	import actionScripts.valueObjects.FileWrapper;
	import actionScripts.valueObjects.ProjectReferenceVO;
	import actionScripts.valueObjects.ProjectVO;
	import actionScripts.valueObjects.ResourceVO;
	import actionScripts.valueObjects.Settings;
	
	import components.popup.ModifiedFileListPopup;
	import components.popup.SDKDefinePopup;
	import components.popup.SDKSelectorPopup;
	import components.renderers.CustomToolTipGBA;
	import components.views.splashscreen.SplashScreen;

	public class UtilsCore 
	{
		public static var wrappersFoundThroughFindingAWrapper:Vector.<FileWrapper>;
		
		private static var sdkPopup:SDKSelectorPopup;
		private static var sdkPathPopup:SDKDefinePopup;
		private static var model:IDEModel = IDEModel.getInstance();
		
		/**
		 * Get data agent error type
		 */
		public static function getDataType(value:String):DataHTMLType
		{
			var dataType:DataHTMLType = new DataHTMLType();
			var message:String;
			
			// true if it's a login agent call
			if ((value.indexOf("/Grails4NotesBroker/admin/auth") != -1) || (value.indexOf("Please Login") != -1))
			{
				// error is a login error
				var indexToStart:int = value.indexOf("<div class='login_message'>");
				if (indexToStart > 0) message = value.substring(indexToStart+27, value.indexOf("</div>", indexToStart));
				else message = "Please, check your username or password.";
				
				dataType.message = message;
				dataType.type = DataHTMLType.LOGIN_ERROR;
				dataType.isError = true;
			}
			else if ((value.toLowerCase().indexOf("authenticated") != -1) || (value.toLowerCase().indexOf("welcome to grails") != -1))
			{
				dataType.isError = false;
				dataType.type = DataHTMLType.LOGIN_SUCCESS;
			}
			else
			{
				dataType.message = "Your session has expired. Please, re-login.";
				dataType.type = DataHTMLType.SESSION_ERROR;
				dataType.isError = true;
			}
			
			return dataType;
		}
		
		/**
		 * Checks through opened project list against
		 * a given path value
		 * @return
		 * BOOL
		 */
		public static function checkProjectIfAlreadyOpened(value:String):Boolean
		{
			for each (var file:AS3ProjectVO in model.projects)
			{
				if (file.folderLocation.fileBridge.nativePath == value)
				{
					return true;
				}
			}
			
			return false;
		}
		
		/**
		 * Creates custom tooltip
		 */
		public static function createCustomToolTip(event:ToolTipEvent):void
		{
			var cTT : CustomToolTipGBA = new CustomToolTipGBA();
			event.toolTip = cTT;
		}
		
		/**
		 * Checks content of files to determine between
		 * binary and text
		 */
		public static function isBinary(fileContent:String):Boolean
		{
			return (/[\x00-\x08\x0E-\x1F]/.test(fileContent));
		}
		
		/**
		 * Positions the toolTip
		 */
		public static function positionTip(event:ToolTipEvent):void
		{
			var tmpPoint : Point = getContentToGlobalXY( event.currentTarget as UIComponent );
			event.toolTip.y = tmpPoint.y + 20;
			event.toolTip.x = event.toolTip.x - 20;
		}
		
		/**
		 * Determines if a project is AIR type
		 */
		public static function isAIR(project:AS3ProjectVO):Boolean
		{
			// giving precedence to the as3proj value
			if (project.swfOutput.platform == SWFOutputVO.PLATFORM_AIR || project.swfOutput.platform == SWFOutputVO.PLATFORM_MOBILE) return true;
			
			if (project.targets.length > 0)
			{
				// considering that application descriptor file should exists in the same
				// root where application source file is exist
				var appFileName:String = project.targets[0].fileBridge.name.split(".")[0];
				if (project.targets[0].fileBridge.parent.fileBridge.resolvePath("application.xml").fileBridge.exists) return true;
				else if (project.targets[0].fileBridge.parent.fileBridge.resolvePath(appFileName +"-app.xml").fileBridge.exists) return true;
			}
			
			if (project.isLibraryProject && project.testMovie == AS3ProjectVO.TEST_MOVIE_AIR) return true;
			
			return false;
		}
		
		/**
		 * Determines if a project is mobile type
		 */
		public static function isMobile(project:AS3ProjectVO):Boolean
		{
			// giving precedence to the as3proj value
			if (project.swfOutput.platform == SWFOutputVO.PLATFORM_MOBILE) return true;
			
			if (project.isLibraryProject)
			{
				if (project.buildOptions.additional && project.buildOptions.additional.indexOf("airmobile") != -1) return true;
			}
			else if (project.sourceFolder && project.sourceFolder.fileBridge.exists)
			{
				var appFileName:String = project.targets[0].fileBridge.name.split(".")[0];
				var descriptor:FileLocation = project.sourceFolder.fileBridge.resolvePath(appFileName +"-app.xml");
				if (descriptor.fileBridge.exists)
				{
					var descriptorData:XML = XML(descriptor.fileBridge.read());
					var tmpNameSearchString:String = "";
					for each (var i:XML in descriptorData.children())
					{
						tmpNameSearchString += i.localName()+" ";
					}
					
					return (tmpNameSearchString.indexOf("android") != -1) || (tmpNameSearchString.indexOf("iPhone") != -1);
				}
			}
			
			return false;
		}
		
		/**
		 * Getting a component co-ordinate
		 * in respect of global stage
		 */
		public static function getContentToGlobalXY(dObject:UIComponent):Point
		{
			var thisHolderPoint : Point = UIComponent(dObject.owner).contentToGlobal( new Point( dObject.x, dObject.y ) );
			var newP : Point = FlexGlobals.topLevelApplication.globalToContent( thisHolderPoint );
			return newP;
		}
		
		/**
		 * Deserializes True and False strings to true and false Boolean values.
		 */
		public static function deserializeBoolean(o:Object):Boolean {
			var str:String = o.toString();
			return str.toLowerCase() == "true";
		}
		/**
		 * Serializes a Boolean value into True or False strings.
		 */
		public static function serializeBoolean(b:Boolean):String {
			return b ? "True" : "False";
		}
		
		/**
		 * Deserialize a String value so it's null when empty
		 */
		public static function deserializeString(o:Object):String {
			var str:String = o.toString();
			if (str.length == 0) return null;
			if (str == "null") return null;
			return str;
		}
		
		/**
		 * Serialize a String value so it's empty when null
		 */
		public static function serializeString(str:String):String {
			return str ? str : "";
		}
		
		/**
		 * Serialize key-value pairs to FD-like XML elements using a template element
		 *  Example:
		 *		<option accessible="True" />
		 *		<option allowSourcePathOverlap="True" />
		 *		<option benchmark="True" />
		 *		<option es="True" />
		 *		<option locale="" />
		 */
		public static function serializePairs(pairs:Object, template:XML):XMLList {
			var list:XML = <xml/>;
			for (var key:String in pairs) {
				var node:XML = template.copy();
				node.@[key] = pairs[key];
				list.appendChild(node);
			}
			return list.children();
		}
		
		public static function fixSlashes(path:String):String
		{
			if (!path) return null;
			
			//path = path.replace(/\//g, IDEModel.getInstance().fileCore.separator);
			if (ConstantsCoreVO.IS_MACOS) path = path.replace(/\\/g, model.fileCore.separator);
			return path;
		}
		
		public static function convertString(path:String):String
		{
			if (Settings.os == "win")
			{
				path= path.split(" ").join("^ ");
				path= path.split("(").join("^(");
				path= path.split(")").join("^)");
				path= path.split("&").join("^&");
			}
			else
			{
				path= path.split(" ").join("\\ ");
				path= path.split("(").join("\\(");
				path= path.split(")").join("\\)");
				path= path.split("&").join("\\&");
			}
			return path;
		}
		
		public static function getUserDefinedSDK(searchByValue:String, searchByField:String):ProjectReferenceVO
		{
			for each (var i:ProjectReferenceVO in model.userSavedSDKs)
			{
				if (i[searchByField] == searchByValue)
				{
					return i;
				}
			}
			// if not found
			return null;
		}
		
		/**
		 * Returns projectVO against fileWrapper
		 */
		public static function getProjectFromProjectFolder(projectFolder:FileWrapper):ProjectVO
		{
			if (!projectFolder) return null;
			
			for each (var p:ProjectVO in model.projects)
			{
				if (p.folderPath == projectFolder.projectReference.path)
					return p;
			}
			
			return null;
		}
		
		/**
		 * Returns the probable SDK against a project
		 */
		public static function getCurrentSDK(pvo:AS3ProjectVO):FileLocation
		{
			return pvo.buildOptions.customSDK ? pvo.buildOptions.customSDK : model.defaultSDK;
		}

		/**
		 * Returns dotted package references
		 * against a project path
		 */
		public static function getPackageReferenceByProjectPath(projectPath:String, filePath:String=null, fileWrapper:FileWrapper=null, fileLocation:FileLocation=null, appendProjectNameAsPrefix:Boolean=true):String
		{
			if (fileWrapper) filePath = fileWrapper.nativePath;
			else if (fileLocation) filePath = fileLocation.fileBridge.nativePath;
			
			var separator:String = model.fileCore.separator;
			var projectPathSplit:Array = projectPath.split(separator);
			filePath = filePath.replace(projectPath, "");
			if (appendProjectNameAsPrefix) return projectPathSplit[projectPathSplit.length-1] + filePath.split(separator).join(".");
			return filePath.split(separator).join(".");
		}
		
		/**
		 * Fine a fileWrapper object
		 * by a fileLocation object
		 */
		public static function findFileWrapperAgainstFileLocation(current:FileWrapper, target:FileLocation):FileWrapper
		{
			// Recurse-find filewrapper child
			for each (var child:FileWrapper in current.children)
			{
				if (target.fileBridge.nativePath == child.nativePath || target.fileBridge.nativePath.indexOf(child.nativePath + target.fileBridge.separator) == 0)
				{
					if (wrappersFoundThroughFindingAWrapper) wrappersFoundThroughFindingAWrapper.push(child);
					if (target.fileBridge.nativePath == child.nativePath) 
					{
						return child;
					}
					if (child.children && child.children.length > 0) return findFileWrapperAgainstFileLocation(child, target); 	
				}
			}
			return current;
		}
		
		/**
		 * Find a fileWrapper object
		 * against a project object
		 */
		public static function findFileWrapperAgainstProject(current:FileWrapper, project:ProjectVO, orInFileWrapper:FileWrapper=null):FileWrapper
		{
			var projectChildren:FileWrapper = project ? project.projectFolder : orInFileWrapper;
			
			// Probable termination
			if (!projectChildren) return current;
			
			// Recurse-find filewrapper child
			wrappersFoundThroughFindingAWrapper = new Vector.<FileWrapper>();
			for each (var ownerWrapper:FileWrapper in projectChildren.children)
			{
				if (current.file.fileBridge.nativePath == ownerWrapper.nativePath || current.file.fileBridge.nativePath.indexOf(ownerWrapper.nativePath + current.file.fileBridge.separator) == 0)
				{
					wrappersFoundThroughFindingAWrapper.push(ownerWrapper);
					if (current.file.fileBridge.nativePath == ownerWrapper.nativePath) 
					{
						return ownerWrapper;
					}
					if (ownerWrapper.children && ownerWrapper.children.length > 0) 
					{
						var tmpMultiReturn:FileWrapper = findFileWrapperAgainstFileLocation(ownerWrapper, current.file);
						if (tmpMultiReturn != ownerWrapper) return tmpMultiReturn;
					}
				}
			}
			return current;
		}
		
		/**
		 * Another way of finding fileWrapper
		 * inside the project hierarchy
		 */
		public static function findFileWrapperInDepth(wrapper:FileWrapper, searchPath:String, project:ProjectVO=null):FileWrapper
		{
			var projectChildren:FileWrapper = project ? project.projectFolder : wrapper;
			for each (var child:FileWrapper in projectChildren.children)
			{
				if (searchPath == child.nativePath || searchPath.indexOf(child.nativePath + child.file.fileBridge.separator) == 0)
				{
					wrappersFoundThroughFindingAWrapper.push(child);
					if (searchPath == child.nativePath) 
					{
						return child;
					}
					if (child.children && child.children.length > 0) return findFileWrapperInDepth(child, searchPath);
				}
			}
			
			return wrapper;
		}
		
		/**
		 * Finding fileWrapper by its UDID
		 */
		public static function findFileWrapperIndexByID(wrapperToSearch:FileWrapper, searchIn:ICollectionView):int
		{
			var uidToSearch:String = UIDUtil.getUID(wrapperToSearch);
			for (var i:String in searchIn)
			{
				if (UIDUtil.getUID(searchIn[i]) == uidToSearch) return int(i);
			}
			
			return -1;
		}
		
		/**
		 * Validate a given path compared with a project's
		 * default source path
		 */
		public static function validatePathAgainstSourceFolder(project:ProjectVO, wrapperToCompare:FileWrapper=null, locationToCompare:FileLocation=null, pathToCompare:String=null):Boolean
		{
			if (wrapperToCompare) pathToCompare = wrapperToCompare.nativePath + project.folderLocation.fileBridge.separator;
			else if (locationToCompare) pathToCompare = locationToCompare.fileBridge.nativePath + project.folderLocation.fileBridge.separator;
			
			// if no sourceFolder exists at all let add file anywhere
			if (!(project as AS3ProjectVO).sourceFolder) return true;
			
			if (pathToCompare.indexOf((project as AS3ProjectVO).sourceFolder.fileBridge.nativePath + project.folderLocation.fileBridge.separator) == -1)
			{
				return false;
			}
			
			return true;
		}
		
		public static function sdkSelection():void
		{
			if (!sdkPathPopup)
			{
				if(!sdkPopup)
				{
					sdkPopup = PopUpManager.createPopUp(FlexGlobals.topLevelApplication as DisplayObject, SDKSelectorPopup, false) as SDKSelectorPopup;
					sdkPopup.addEventListener(ProjectEvent.FLEX_SDK_UDPATED, onFlexSDKUpdated);
					sdkPopup.addEventListener(CloseEvent.CLOSE, onSDKPopupClosed);
					PopUpManager.centerPopUp(sdkPopup);
				}
				else
				{
					PopUpManager.bringToFront(sdkPopup);
				}
			}
			else
			{
				PopUpManager.bringToFront(sdkPathPopup);
			}
			
			function onFlexSDKUpdated(event:ProjectEvent):void
			{
				onSDKPopupClosed(null);
			}
			function onSDKPopupClosed(event:CloseEvent):void
			{
				sdkPopup.removeEventListener(CloseEvent.CLOSE, onSDKPopupClosed);
				sdkPopup.removeEventListener(ProjectEvent.FLEX_SDK_UDPATED, onFlexSDKUpdated);
				sdkPopup = null;
			}
		}
		
		/**
		 * Checks if code-completion requisite FlexJS 
		 * available or not and returns
		 */
		public static function checkCodeCompletionFlexJSSDK():String
		{
			var hasFlex:Boolean = false;
			var FLEXJS_NAME_PREFIX:String = "Apache Flex (FlexJS) ";
			
			var path:String;
			var bestVersionValue:int = 0;
			for each (var i:ProjectReferenceVO in model.userSavedSDKs)
			{
				var sdkName:String = i.name;
				if (sdkName.indexOf(FLEXJS_NAME_PREFIX) != -1)
				{
					var sdkVersion:String = sdkName.substr(FLEXJS_NAME_PREFIX.length, sdkName.indexOf(" ", FLEXJS_NAME_PREFIX.length) - FLEXJS_NAME_PREFIX.length);
					var versionParts:Array = sdkVersion.split("-")[0].split(".");
					var major:int = 0;
					var minor:int = 0;
					var revision:int = 0;
					if (versionParts.length >= 3)
					{
						major = parseInt(versionParts[0], 10);
						minor = parseInt(versionParts[1], 10);
						revision = parseInt(versionParts[2], 10);
					}
					//FlexJS 0.7.0 is the minimum version supported by the
					//language server. this may change in the future.
					if (major > 0 || minor >= 7)
					{
						//convert the three parts of the version number
						//into a single value to compare to other versions.
						var currentValue:int = major * 1e6 + minor * 1000 + revision;
						if(bestVersionValue < currentValue)
						{
							//pick the newest available version of FlexJS
							//to power the language server.
							hasFlex = true;
							path = i.path;
							bestVersionValue = currentValue;
							model.isCodeCompletionJavaPresent = true;
						}
					}
				}
			}
			
			return path;
		}
		
		/**
		 * Returns BOOL if version is newer than
		 * given version
		 * 
		 * Basically requires for FlexJS version check where
		 * 0.8.0 added new compiler argument which do not works
		 * in older versions
		 */
		public static function isNewerVersionSDKThan(olderVersion:int, sdkPath:String):Boolean
		{
			if (!sdkPath) return false;
			
			// we need some extra work to determine if FlexJS version is lower than 0.8.0
			// to ensure addition of new compiler argument '-compiler.targets' 
			// which do not works with SDK < 0.8.0
			var sdkFullName:String;
			for each (var project:ProjectReferenceVO in model.userSavedSDKs)
			{
				if (sdkPath == project.path)
				{
					sdkFullName = project.name;
					break;
				}
			}

            var flexJSPrefixName:String = "Apache Flex (FlexJS) ";
            var royalePrefixName:String = "Apache Royale ";

            var isValidSdk:Boolean = false;
			if (sdkFullName.indexOf(flexJSPrefixName) > -1)
			{
				isValidSdk = true;
			}
			else if (sdkFullName.indexOf(royalePrefixName) > -1)
			{
				return true;
			}

			if (isValidSdk)
            {
                var sdkNamePrefixLength:int = flexJSPrefixName.length;

				var sdkVersion:String = sdkFullName.substr(sdkNamePrefixLength,
						sdkFullName.indexOf(" ", sdkNamePrefixLength) - sdkNamePrefixLength);
				var versionParts:Array = sdkVersion.split("-")[0].split(".");
				var major:int = 0;
				var minor:int = 0;

				if (versionParts.length >= 3)
				{
					major = parseInt(versionParts[0], 10);
					minor = parseInt(versionParts[1], 10);
				}

				if (major > 0 || minor > olderVersion)
				{
					return true;
				}
            }

			return false;
		}
		
		/**
		 * Sets requisite flags based on application file's tag
		 * Required - AS3ProjectVO
		 */
		public static function checkIfRoyaleApplication(project:AS3ProjectVO):void
		{
            // probable termination
            if (project.targets.length == 0 || !project.targets[0].fileBridge.exists) return;

            var mainAppContent:String = project.targets[0].fileBridge.read() as String;
			var isMdlApp:Boolean = mainAppContent.indexOf("mdl:Application") > -1;
			var isJewelApp:Boolean = mainAppContent.indexOf("j:Application") > -1;
            var hasExpressNamespace:Boolean = mainAppContent.indexOf("library://ns.apache.org/royale/express") > -1;
		    var hasRoyaleNamespace:Boolean = mainAppContent.indexOf("library://ns.apache.org/royale/basic") > -1 || hasExpressNamespace;
			var hasFlexJSNamespace:Boolean = mainAppContent.indexOf("library://ns.apache.org/flexjs/basic") > -1;
			var hasJewelNamespace:Boolean = mainAppContent.indexOf("library://ns.apache.org/royale/jewel") > -1;

            if ((mainAppContent.indexOf("js:Application") > -1 || isMdlApp || isJewelApp) &&
				(hasFlexJSNamespace || hasRoyaleNamespace || hasExpressNamespace || hasJewelNamespace))
            {
                // FlexJS Application
                project.isFlexJS  = true;
				project.isRoyale = hasRoyaleNamespace || hasJewelNamespace;
				
                // FlexJS MDL applicaiton
                project.isMDLFlexJS = isMdlApp;
            }
            else
            {
                project.isFlexJS = project.isMDLFlexJS = project.isRoyale = false;
            }
		}
		
		/**
		 * Returns possible Java exeuctable in system
		 */
		public static function getJavaPath():FileLocation
		{
			var executableFile:FileLocation;
			
			if (ConstantsCoreVO.IS_MACOS) executableFile = new FileLocation("/usr/bin/java");
			else 
			{
				if (model.javaPathForTypeAhead && model.javaPathForTypeAhead.fileBridge.exists) 
				{
					executableFile = new FileLocation(model.javaPathForTypeAhead.fileBridge.nativePath +"\\bin\\javaw.exe");
					if (!executableFile.fileBridge.exists) executableFile = new FileLocation(model.javaPathForTypeAhead.fileBridge.nativePath +"\\javaw.exe"); // in case of user setup by 'javaPath/bin'
				}
				else
				{
					var javaFolder:String = Capabilities.supports64BitProcesses ? "Program Files (x86)" : "Program Files";
					var tmpJavaLocation:FileLocation = new FileLocation("C:/"+ javaFolder +"/Java");
					if (tmpJavaLocation.fileBridge.exists)
					{
						var javaFiles:Array = tmpJavaLocation.fileBridge.getDirectoryListing();
						for each (var j:Object in javaFiles)
						{
							if (j.nativePath.indexOf("jre") != -1)
							{
								executableFile = new FileLocation(j.nativePath +"\\bin\\javaw.exe");
								break;
							}
						}
					}
				}
			}
			
			// finally
			return executableFile;
		}
		
		/**
		 * Closes all the opened editors relative to a certain project path
		 */
		public static function closeAllRelativeEditors(projectOrWrapper:Object, isSkipSaveConfirmation:Boolean=false,
													   completionHandler:Function=null, isCloseWhenDone:Boolean=true):void
		{
			var projectReferencePath:String;
			var editorsCount:int = model.editors.length;
			var hasChangesEditors:ArrayCollection = new ArrayCollection();
			var editorsToClose:Array = [];
			
			// closes all opened file editor instances belongs to the deleted project
			// closing is IMPORTANT
			// if projectOrWrapper==null, it'll close all opened editors irrespective of 
			// any particular project (example usage in 'Close All' option in File menu)
			if (projectOrWrapper)
			{
				if (projectOrWrapper is ProjectVO) projectReferencePath = (projectOrWrapper as ProjectVO).folderLocation.fileBridge.nativePath;
				else if (projectOrWrapper is FileWrapper && (projectOrWrapper as FileWrapper).projectReference) projectReferencePath = (projectOrWrapper as FileWrapper).projectReference.path;
			}
			
			for (var i:int = 0; i < editorsCount; i++)
			{
				if ((model.editors[i] is BasicTextEditor) && model.editors[i].currentFile && (!projectReferencePath || model.editors[i].projectPath == projectReferencePath))
				{
                    var editor:BasicTextEditor = model.editors[i];
					if (editor)
					{
						editorsToClose.push(editor);
						if (!isSkipSaveConfirmation && editor.isChanged())
						{
							hasChangesEditors.addItem({file:editor, isSelected:true});
                        }
					}
				}
				else if (model.editors[i] is SettingsView && model.editors[i].associatedData && (!projectReferencePath || AS3ProjectVO(model.editors[i].associatedData).folderLocation.fileBridge.nativePath == projectReferencePath))
				{
					editorsToClose.push(model.editors[i]);
					if (!isSkipSaveConfirmation && model.editors[i].isChanged())
					{
						hasChangesEditors.addItem({file:model.editors[i], isSelected:true});
                    }
				}
				else if (model.editors[i].hasOwnProperty("label") && ConstantsCoreVO.NON_CLOSEABLE_TABS.indexOf(model.editors[i].label) == -1)
				{
					if (!isSkipSaveConfirmation && model.editors[i].isChanged())
					{
						hasChangesEditors.addItem({file:model.editors[i], isSelected:true});
					}
					else if (projectOrWrapper == null && completionHandler == null && model.editors[i] != SplashScreen)
					{
						editorsToClose.push(model.editors[i]);
					}
				}
			}
			
			// check if the editors has any changes
			if (!isSkipSaveConfirmation && hasChangesEditors.length > 0)
			{
				var modListPopup:ModifiedFileListPopup = PopUpManager.createPopUp(FlexGlobals.topLevelApplication as DisplayObject, ModifiedFileListPopup, true) as ModifiedFileListPopup;
				modListPopup.collection = hasChangesEditors;
				modListPopup.addEventListener(CloseEvent.CLOSE, onModListClosed);
				PopUpManager.centerPopUp(modListPopup);
			}
			else
			{
				onModListClosed(null);
			}
			
			/*
			 * @local
			 */
			function onModListClosed(event:CloseEvent):void
			{
				if (event) event.target.removeEventListener(CloseEvent.CLOSE, onModListClosed);
				
				// in case we just want save process to the unsaved editors
				// but not to close the editors when done 
				// default - true
				if (isCloseWhenDone)
                {
                    // close all the tabs without waiting for anything further
                    for each (var j:IContentWindow in editorsToClose)
                    {
                        GlobalEventDispatcher.getInstance().dispatchEvent(
                                new CloseTabEvent(CloseTabEvent.EVENT_CLOSE_TAB, j as DisplayObject, true)
                        );
                    }
                }
				
				// notify the caller
				if (completionHandler != null) completionHandler();
			}
		}
		
		/**
		 * Parse all acceptable files in a given project
		 */
		public static function parseFilesList(collection:IList, project:ProjectVO=null, readableExtensions:Array=null, isSourceFolderOnly:Boolean=false):void
		{
			if (project)
			{
				if (isSourceFolderOnly && (project as AS3ProjectVO).sourceFolder) 
				{
					// lets search for the probable existing fileWrapper object
					// instead of creating a new one - that could be expensive
					var sourceWrapper:FileWrapper = findFileWrapperAgainstFileLocation(project.projectFolder, (project as AS3ProjectVO).sourceFolder);
					if (sourceWrapper) 
					{
						parseChildrens(sourceWrapper, collection, readableExtensions);
						return;
					}
				}
				
				parseChildrens(project.projectFolder, collection, readableExtensions);
			}
			else
			{
				for each (var i:ProjectVO in model.projects)
				{
					parseChildrens(i.projectFolder, collection, readableExtensions);
				}
			}
		}
		private static function parseChildrens(value:FileWrapper, collection:IList, readableExtensions:Array=null):void
		{
			if (!value) return;
			
			var extension:String = value.file.fileBridge.extension;
			if (!value.file.fileBridge.isDirectory && (extension != null) && isAcceptableResource(extension))
			{
				collection.addItem(new ResourceVO(value.file.fileBridge.name, value));
				return;
			}
			
			if ((value.children is Array) && (value.children as Array).length > 0)
			{
				for each (var c:FileWrapper in value.children)
				{
					extension = c.file.fileBridge.extension;
					if (!c.file.fileBridge.isDirectory && (extension != null) && isAcceptableResource(extension, readableExtensions))
					{
						collection.addItem(new ResourceVO(c.file.fileBridge.name, c));
					}
					else if (c.file.fileBridge.isDirectory)
					{
						parseChildrens(c, collection, readableExtensions);
					}
				}
			}
		}
		private static function isAcceptableResource(extension:String, readableExtensions:Array=null):Boolean
		{
			readableExtensions ||= ConstantsCoreVO.READABLE_FILES;
			return readableExtensions.some(
				function isValidExtension(item:Object, index:int, arr:Array):Boolean {
					return item == extension;
				});
		}
		
		/**
		 * Returns menu options on current
		 * recent opened projects
		 */
		public static function getRecentProjectsMenu():MenuItem
		{
			var openRecentLabel:String = ResourceManager.getInstance().getString('resources','OPEN_RECENT_PROJECTS');
			var openProjectMenu:MenuItem = new MenuItem(openRecentLabel);
			openProjectMenu.parents = ["File", openRecentLabel];
			openProjectMenu.items = new Vector.<MenuItem>();
			
			for each (var i:ProjectReferenceVO in model.recentlyOpenedProjects)
			{
				if (i.name)
				{
					var menuItem:MenuItem = new MenuItem(i.name, null, null, "eventOpenRecentProject");
					menuItem.data = i; 
					openProjectMenu.items.push(menuItem);
				}
			}
			
			return openProjectMenu;
		}
		
		/**
		 * Returns menu options on current
		 * recent opened projects
		 */
		public static function getRecentFilesMenu():MenuItem
		{
			var openRecentLabel:String = ResourceManager.getInstance().getString('resources','OPEN_RECENT_FILES');
			var openFileMenu:MenuItem = new MenuItem(openRecentLabel);
			openFileMenu.parents = ["File", openRecentLabel];
			openFileMenu.items = new Vector.<MenuItem>();
			
			for each (var i:ProjectReferenceVO in model.recentlyOpenedFiles)
			{
				if (i.name)
				{
					var menuItem:MenuItem = new MenuItem(i.name, null, null, "eventOpenRecentFile");
					menuItem.data = i; 
					openFileMenu.items.push(menuItem);
				}
			}
			
			return openFileMenu;
		}
		
		/**
		 * Set project menu type based on possible field
		 */
		public static function setProjectMenuType(value:AS3ProjectVO):void
		{
			if (value.isFlexJS || value.isRoyale || value.isMDLFlexJS) value.menuType = ProjectMenuTypes.JS_ROYALE;
			else if (value.isLibraryProject) value.menuType = ProjectMenuTypes.LIBRARY_FLEX_AS;
			else if (value.isPrimeFacesVisualEditorProject) value.menuType = ProjectMenuTypes.VISUAL_EDITOR_PRIMEFACES;
			else if (value.isVisualEditorProject) value.menuType = ProjectMenuTypes.VISUAL_EDITOR_FLEX;
			else value.menuType = ProjectMenuTypes.FLEX_AS;
			
			// git check
			GlobalEventDispatcher.getInstance().dispatchEvent(new ProjectEvent(ProjectEvent.CHECK_GIT_PROJECT, value));
		}
		
		/**
		 * Returns encoded string to run on Windows' shell
		 */
		public static function getEncodedForShell(value:String):String
		{
			var tmpValue:String = "";
			if (ConstantsCoreVO.IS_MACOS)
			{
				// @important
				// assuming the content will be double-quoted by the caller function
				tmpValue = value.replace(/(")/g, '\\"');
			}
			else
			{
				for (var i:int; i < value.length; i++)
				{
					tmpValue += "^"+ value.charAt(i);
				}
			}
			
			return tmpValue;
		}
	}
}