////////////////////////////////////////////////////////////////////////////////
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
package actionScripts.plugins.as3project
{
    import com.adobe.utils.StringUtil;
    
    import flash.events.Event;
    import flash.filesystem.File;
    import flash.net.SharedObject;
    
    import mx.controls.Alert;
    
    import actionScripts.events.AddTabEvent;
    import actionScripts.events.GlobalEventDispatcher;
    import actionScripts.events.ProjectEvent;
    import actionScripts.extResources.deng.fzip.fzip.FZipFile;
    import actionScripts.factory.FileLocation;
    import actionScripts.locator.IDEModel;
    import actionScripts.plugin.actionscript.as3project.vo.AS3ProjectVO;
    import actionScripts.plugin.settings.SettingsView;
    import actionScripts.plugin.settings.vo.AbstractSetting;
    import actionScripts.plugin.settings.vo.ISetting;
    import actionScripts.plugin.settings.vo.PathSetting;
    import actionScripts.plugin.settings.vo.SettingsWrapper;
    import actionScripts.plugin.settings.vo.StaticLabelSetting;
    import actionScripts.plugin.settings.vo.StringSetting;
    import actionScripts.plugins.as3project.importer.FlashBuilderImporter;
    import actionScripts.plugins.as3project.importer.FlashDevelopImporter;
    import actionScripts.ui.tabview.CloseTabEvent;
    import actionScripts.utils.SharedObjectConst;
    import actionScripts.utils.Unzip;
	
    public class ImportArchiveProject
	{
		private var newProjectNameSetting:StringSetting;
		private var newProjectPathSetting:PathSetting;
		private var cookie:SharedObject;
		private var project:AS3ProjectVO;
		private var model:IDEModel = IDEModel.getInstance();
		private var dispatcher:GlobalEventDispatcher = GlobalEventDispatcher.getInstance();
		private var unzip:Unzip;
		private var settingsView:SettingsView;
		
		private var _customFlexSDK:String;
		private var _currentCauseToBeInvalid:String;
		private var _archivePath:String;
		private var _projectName:String;
		private var _folderPath:String;
		
		public function ImportArchiveProject()
		{
			openImportProjectWindow();
		}
		
		public function get projectName():String
		{
			return _projectName;
		}
		public function set projectName(value:String):void
		{
			_projectName = value;
		}
		
		public function get folderPath():String
		{
			return _folderPath;
		}
		public function set folderPath(value:String):void
		{
			_folderPath = value;
		}
		
		public function get archivePath():String
		{
			return _archivePath;
		}
		public function set archivePath(value:String):void
		{
			_archivePath = value;
		}
		
		public function get customFlexSDK():String
		{
			return _customFlexSDK;
		}
		public function set customFlexSDK(value:String):void
		{
			_customFlexSDK = value;
		}
		
		private function get isInvalidToSave():Boolean
		{
			if ((!folderPath || StringUtil.trim(folderPath).length == 0) ||
				(!projectName || StringUtil.trim(projectName).length == 0) ||
				(!archivePath || StringUtil.trim(archivePath).length == 0))
			{
				_currentCauseToBeInvalid = "Not enough information.";
				return true;
			}
			return false;
		}
		
		private function testArchivePath():void
		{
			unzip = new Unzip(new File(archivePath));
			unzip.addEventListener(Unzip.FILE_LOAD_SUCCESS, onFileLoadSuccess);
			unzip.addEventListener(Unzip.FILE_LOAD_ERROR, onFileLoadError);
			
			/*
			 * @local
			 */
			function onFileLoadSuccess(ev:Event):void
			{
				releaseListeners();
				
				// verify if known project archive as per
				// FlashDevelopImporter.test()
				var tmpFiles:Array = unzip.getFilesList();
				if (tmpFiles)
				{
					var extension:String;
					for each (var file:FZipFile in tmpFiles)
					{
						// we don't provide by easy extension property by the api
						if (!file.isDirectory)
						{
							extension = file.extension;
							if (extension == "as3proj" || extension == "veditorproj")
							{
								// TODO::
								// we need to decide on which level of folder/sub-folder we 
								// should check to determine if a valid project archive, i.e.
								// a project configuration file can exists to the root of zip file
								// or it can resides somewhere inside some sub-folder. 
								// since per existing valid project folder rule, the configuration
								// file is suppose to exist to the project root, we need to decide on -
								// 1. if we want to check the configuration only to root or to any sub-folder
								// 2. if configuration found in sub-folder, shall we taken that sub-folder is the root of a project?
								
								// for now, let's continue if valid project archive
								createSaveContinue();
								return;
							}
						}
					}
					
					// if came through here, it's not a valid project archive
					Alert.show("No valid Moonshine project found to the archive. Please check.", "Error!");
				}
			}
			function onFileLoadError(ev:Event):void
			{
				releaseListeners();
				Alert.show("Unable to load the archive file.\nPlease check, if the file is valid or exist to the path.", "Error!");
			}
			function releaseListeners():void
			{
				unzip.removeEventListener(Unzip.FILE_LOAD_SUCCESS, onFileLoadSuccess);
				unzip.removeEventListener(Unzip.FILE_LOAD_ERROR, onFileLoadError);
			}
		}
		
		private function openImportProjectWindow():void
		{
			var lastSelectedProjectPath:String;

			CONFIG::OSX
				{
					if (OSXBookmarkerNotifiers.availableBookmarkedPaths == "") OSXBookmarkerNotifiers.removeFlashCookies();
				}
			
            cookie = SharedObject.getLocal(SharedObjectConst.MOONSHINE_IDE_LOCAL);
			if (cookie.data.hasOwnProperty('recentProjectPath'))
			{
				model.recentSaveProjectPath.source = cookie.data.recentProjectPath;
				if (cookie.data.hasOwnProperty('lastSelectedProjectPath')) 
				{
					lastSelectedProjectPath = cookie.data.lastSelectedProjectPath;
					if (!folderPath && lastSelectedProjectPath) 
					{
						folderPath = (model.recentSaveProjectPath.getItemIndex(lastSelectedProjectPath) != -1) ? lastSelectedProjectPath : model.recentSaveProjectPath.source[model.recentSaveProjectPath.length - 1];
					}
				}
			}
			
			settingsView = new SettingsView();
			settingsView.Width = 150;
			settingsView.defaultSaveLabel = "Import";
			settingsView.isNewProjectSettings = true;
			
			settingsView.addCategory("");

			var settings:SettingsWrapper = getProjectSettings();
			settingsView.addEventListener(SettingsView.EVENT_SAVE, createSavePreparation);
			settingsView.addEventListener(SettingsView.EVENT_CLOSE, createClose);
			settingsView.addSetting(settings, "");
			
			settingsView.label = "Import Project";
			newProjectPathSetting.setMessage((folderPath ? folderPath : ".. ") + model.fileCore.separator +" ..");
			
			dispatcher.dispatchEvent(
				new AddTabEvent(settingsView)
			);
		}

        private function isAllowedTemplateFile(projectFileExtension:String):Boolean
        {
            return projectFileExtension != "as3proj" || projectFileExtension != "veditorproj" || !projectFileExtension;
        }

		private function getProjectSettings():SettingsWrapper
		{
            newProjectNameSetting = new StringSetting(this, 'projectName', 'Project name', '^ ~`!@#$%\\^&*()\\-+=[{]}\\\\|:;\'",<.>/?');
			newProjectPathSetting = new PathSetting(this, 'folderPath', 'Directory to Save', true, null, false, true);
			newProjectPathSetting.addEventListener(AbstractSetting.PATH_SELECTED, onProjectPathChanged);
			newProjectNameSetting.addEventListener(StringSetting.VALUE_UPDATED, onProjectNameChanged);
			
			var archivePathSetting:PathSetting = new PathSetting(this, 'archivePath', 'Archive File to Project', false);
			archivePathSetting.fileFilters = ["*.zip"];

            return new SettingsWrapper("Name & Location", Vector.<ISetting>([
				new StaticLabelSetting('Import an Archive Project'),
				newProjectNameSetting, // No space input either plx
				archivePathSetting,
				newProjectPathSetting,
				new PathSetting(this,'customFlexSDK', 'Apache Flex®, Apache Royale® or Feathers SDK', true, customFlexSDK, true)
			]));
		}
		
		private function checkIfProjectDirectory(value:File):void
		{
			var tmpFile:FileLocation = FlashDevelopImporter.test(value);
			if (!tmpFile) tmpFile = FlashBuilderImporter.test(value);
			
			if (tmpFile) 
			{
				newProjectPathSetting.setMessage((_currentCauseToBeInvalid = "Project can not be created to an existing project directory:\n"+ value.nativePath), AbstractSetting.MESSAGE_CRITICAL);
			}
			else newProjectPathSetting.setMessage(value.nativePath);
			
			if (newProjectPathSetting.stringValue == "") 
			{
				_currentCauseToBeInvalid = 'Unable to access Project Directory:\n'+ value.nativePath +'\nPlease try to create the project again and use the "Change" link to open the target directory again.';
			}
		}

		//--------------------------------------------------------------------------
		//
		//  PRIVATE LISTENERS
		//
		//--------------------------------------------------------------------------
		
		private function onProjectPathChanged(event:Event, makeNull:Boolean=true):void
		{
			return; // temp
			
			if (makeNull) project.projectFolder = null;
			project.folderLocation = new FileLocation(newProjectPathSetting.stringValue);
			newProjectPathSetting.label = "Parent Directory";
			checkIfProjectDirectory(project.folderLocation.resolvePath(newProjectNameSetting.stringValue));
		}
		
		private function onProjectNameChanged(event:Event):void
		{
			if (folderPath)
			{
				checkIfProjectDirectory((new File(folderPath)).resolvePath(newProjectNameSetting.stringValue));
			}
		}
		
		private function createClose(event:Event):void
		{
			settingsView.removeEventListener(SettingsView.EVENT_CLOSE, createClose);
			settingsView.removeEventListener(SettingsView.EVENT_SAVE, createSavePreparation);
			if (newProjectPathSetting) 
			{
				newProjectPathSetting.removeEventListener(AbstractSetting.PATH_SELECTED, onProjectPathChanged);
				newProjectNameSetting.removeEventListener(StringSetting.VALUE_UPDATED, onProjectNameChanged);
			}
			
			dispatcher.dispatchEvent(
				new CloseTabEvent(CloseTabEvent.EVENT_CLOSE_TAB, settingsView)
			);
		}
		
		private function throwError():void
		{
			Alert.show(_currentCauseToBeInvalid +" Project creation terminated.", "Error!");
		}
		
		private function createSavePreparation(event:Event):void
		{
			if (isInvalidToSave) 
			{
				throwError();
				return;
			}
			
			testArchivePath();
		}
		
		private function createSaveContinue():void
		{
			// create destination folder by projectName
			var destinationProjectFolder:File = (new File(folderPath)).resolvePath(projectName);
			destinationProjectFolder.createDirectory();
			
			unzip.unzipTo(destinationProjectFolder, onUnzipSuccess);
		}
		
		private function onUnzipSuccess(destination:File):void
		{
			dispatcher.dispatchEvent(new ProjectEvent(ProjectEvent.EVENT_IMPORT_PROJECT_NO_BROWSE_DIALOG, destination));
			// close settings view
			createClose(null);
		}
    }
}