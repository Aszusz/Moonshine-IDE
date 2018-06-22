////////////////////////////////////////////////////////////////////////////////
// Copyright 2016 Prominic.NET, Inc.
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
// Author: Prominic.NET, Inc.
// No warranty of merchantability or fitness of any kind. 
// Use this software at your own risk.
////////////////////////////////////////////////////////////////////////////////
package actionScripts.plugins.git
{
	import flash.display.DisplayObject;
	import flash.events.Event;
	
	import mx.collections.ArrayCollection;
	import mx.controls.Alert;
	import mx.core.FlexGlobals;
	import mx.events.CloseEvent;
	import mx.managers.PopUpManager;
	
	import actionScripts.events.GeneralEvent;
	import actionScripts.events.ProjectEvent;
	import actionScripts.plugin.IPlugin;
	import actionScripts.plugin.PluginBase;
	import actionScripts.plugin.actionscript.as3project.vo.AS3ProjectVO;
	import actionScripts.plugin.settings.ISettingsProvider;
	import actionScripts.plugin.settings.event.SetSettingsEvent;
	import actionScripts.plugin.settings.vo.ISetting;
	import actionScripts.plugin.settings.vo.PathSetting;
	import actionScripts.ui.menu.vo.ProjectMenuTypes;
	import actionScripts.valueObjects.ConstantsCoreVO;
	
	import components.popup.GitAuthenticationPopup;
	import components.popup.GitCommitSelectionPopup;
	import components.popup.GitRepositoryPermissionPopup;
	import components.popup.GitXCodePermissionPopup;
	import components.popup.SourceControlCheckout;

    public class GitHubPlugin extends PluginBase implements IPlugin, ISettingsProvider
	{
		public static const CLONE_REQUEST:String = "cloneRequest";
		public static const CHECKOUT_REQUEST:String = "checkoutRequestEvent";
		public static const COMMIT_REQUEST:String = "commitRequest";
		public static const PULL_REQUEST:String = "pullRequest";
		public static const PUSH_REQUEST: String = "pushRequest";
		public static const REFRESH_STATUS_REQUEST:String = "refreshStatusRequest";
		public static const NEW_BRANCH_REQUEST:String = "newBranchRequest";
		public static const CHANGE_BRANCH_REQUEST:String = "changeBranchRequest";
		
		override public function get name():String			{ return "GitHub"; }
		override public function get author():String		{ return "Moonshine Project Team"; }
		override public function get description():String	{ return "GitHub Plugin. Esc exits."; }
		
		public var gitBinaryPathOSX:String;
		
		private var isGitAvailable:Boolean;
		private var checkoutWindow:SourceControlCheckout;
		private var xCodePermissionWindow:GitXCodePermissionPopup;
		private var gitRepositoryPermissionWindow:GitRepositoryPermissionPopup;
		private var gitCommitWindow:GitCommitSelectionPopup;
		private var gitAuthWindow:GitAuthenticationPopup;
		
		private var _processManager:GitProcessManager;
		protected function get processManager():GitProcessManager
		{
			if (!_processManager) 
			{
				_processManager = new GitProcessManager();
				_processManager.setGitAvailable = setGitAvailable;
			}
			
			if (gitBinaryPathOSX) _processManager.gitBinaryPathOSX = gitBinaryPathOSX;
			return _processManager;
		}
		
		override public function activate():void
		{
			super.activate();
			
			dispatcher.addEventListener(CLONE_REQUEST, onCloneRequest, false, 0, true);
			dispatcher.addEventListener(CHECKOUT_REQUEST, onCheckoutRequest, false, 0, true);
			dispatcher.addEventListener(COMMIT_REQUEST, onCommitRequest, false, 0, true);
			dispatcher.addEventListener(PULL_REQUEST, onPullRequest, false, 0, true);
			dispatcher.addEventListener(PUSH_REQUEST, onPushRequest, false, 0, true);
			dispatcher.addEventListener(REFRESH_STATUS_REQUEST, onRefreshRequest, false, 0, true);
			dispatcher.addEventListener(NEW_BRANCH_REQUEST, onNewBranchRequest, false, 0, true);
			dispatcher.addEventListener(CHANGE_BRANCH_REQUEST, onChangeBranchRequest, false, 0, true);
			dispatcher.addEventListener(ProjectEvent.CHECK_GIT_PROJECT, onMenuTypeUpdateAgainstGit, false, 0, true);
		}
		
		override public function deactivate():void 
		{
			super.deactivate();
			
			dispatcher.removeEventListener(CLONE_REQUEST, onCloneRequest);
			dispatcher.removeEventListener(CHECKOUT_REQUEST, onCheckoutRequest);
			dispatcher.removeEventListener(COMMIT_REQUEST, onCommitRequest);
			dispatcher.removeEventListener(PULL_REQUEST, onPullRequest);
			dispatcher.removeEventListener(PUSH_REQUEST, onPushRequest);
			dispatcher.removeEventListener(REFRESH_STATUS_REQUEST, onRefreshRequest);
			dispatcher.removeEventListener(NEW_BRANCH_REQUEST, onNewBranchRequest);
			dispatcher.removeEventListener(CHANGE_BRANCH_REQUEST, onChangeBranchRequest);
			dispatcher.removeEventListener(ProjectEvent.CHECK_GIT_PROJECT, onMenuTypeUpdateAgainstGit);
		}
		
		override public function resetSettings():void
		{
			gitBinaryPathOSX = null;
		}
		
		public function getSettingsList():Vector.<ISetting>
		{
			return Vector.<ISetting>([
				new PathSetting(this,'gitBinaryPathOSX', 'macOS Git Path', true, gitBinaryPathOSX, true)
			]);
		}
		
		protected function setGitAvailable(value:Boolean):void
		{
			isGitAvailable = value;
			if (checkoutWindow) checkoutWindow.isGitAvailable = isGitAvailable;
			if (gitAuthWindow) gitAuthWindow.isGitAvailable = isGitAvailable;
		}
		
		private function checkOSXGitAccess():Boolean
		{
			if (ConstantsCoreVO.IS_MACOS && !gitBinaryPathOSX) 
			{
				processManager.getOSXCodePath(onXCodePathDetection);
				return false;
			}
			
			return true;
		}
		
		private function onXCodePathDetection(path:String):void
		{
			if (path && !xCodePermissionWindow)
			{
				xCodePermissionWindow = new GitXCodePermissionPopup;
				xCodePermissionWindow.xCodePath = path;
				xCodePermissionWindow.horizontalCenter = xCodePermissionWindow.verticalCenter = 0;
				xCodePermissionWindow.addEventListener(Event.CLOSE, onXCodePermissionClosed, false, 0, true);
				FlexGlobals.topLevelApplication.addElement(xCodePermissionWindow);
			}
		}
		
		private function onXCodePermissionClosed(event:Event):void
		{
			var isDiscarded:Boolean = xCodePermissionWindow.isDiscarded;
			if (!isDiscarded) 
			{
				gitBinaryPathOSX = xCodePermissionWindow.xCodePath +"/Contents/Developer/usr/bin/git";
				Alert.show("Git permission accepted. You can now use Moonshine Git functionalities.", "Success!");
				
				var thisSettings: Vector.<ISetting> = getSettingsList();
				var pathSettingToDefaultSDK:PathSetting = thisSettings[0] as PathSetting;
				dispatcher.dispatchEvent(new SetSettingsEvent(SetSettingsEvent.SAVE_SPECIFIC_PLUGIN_SETTING, null, "actionScripts.plugins.git::GitHubPlugin", thisSettings));
			}
			
			xCodePermissionWindow.removeEventListener(Event.CLOSE, onXCodePermissionClosed);
			FlexGlobals.topLevelApplication.removeElement(xCodePermissionWindow);
			xCodePermissionWindow = null;
		}
		
		private function onCloneRequest(event:Event):void
		{
			if (!checkoutWindow)
			{
				if (!checkOSXGitAccess()) return;
				
				processManager.checkGitAvailability();
				
				checkoutWindow = PopUpManager.createPopUp(FlexGlobals.topLevelApplication as DisplayObject, SourceControlCheckout, false) as SourceControlCheckout;
				checkoutWindow.title = "Clone Repository";
				checkoutWindow.type = SourceControlCheckout.TYPE_GIT;
				checkoutWindow.isGitAvailable = isGitAvailable;
				checkoutWindow.addEventListener(CloseEvent.CLOSE, onCheckoutWindowClosed);
				PopUpManager.centerPopUp(checkoutWindow);
			}
			else
			{
				PopUpManager.bringToFront(checkoutWindow);
			}
		}
		
		private function onCheckoutWindowClosed(event:CloseEvent):void
		{
			var submitObject:Object = checkoutWindow.submitObject;
			
			checkoutWindow.removeEventListener(CloseEvent.CLOSE, onCheckoutWindowClosed);
			PopUpManager.removePopUp(checkoutWindow);
			checkoutWindow = null;
			
			if (submitObject) processManager.clone(submitObject.url, submitObject.target);
		}
		
		private function onCheckoutRequest(event:Event):void
		{
			
		}
		
		private function onCommitRequest(event:Event):void
		{
			if (!gitCommitWindow)
			{
				if (!checkOSXGitAccess()) return;
				
				processManager.checkGitAvailability();
				
				gitCommitWindow = PopUpManager.createPopUp(FlexGlobals.topLevelApplication as DisplayObject, GitCommitSelectionPopup, false) as GitCommitSelectionPopup;
				gitCommitWindow.title = "Commit";
				gitCommitWindow.isGitAvailable = isGitAvailable;
				gitCommitWindow.addEventListener(CloseEvent.CLOSE, onGitCommitWindowClosed);
				PopUpManager.centerPopUp(gitCommitWindow);
				
				// we let the popup opened completely
				// then run the following process else
				// there could be a hold before appearing
				// the window until folling process is finished
				gitCommitWindow.callLater(function():void
				{
					processManager.checkDiff();
					if (!processManager.hasEventListener(GitProcessManager.GIT_DIFF_CHECKED))
						processManager.addEventListener(GitProcessManager.GIT_DIFF_CHECKED, onGitDiffChecked, false, 0, true);
				});
			}
			else
			{
				PopUpManager.bringToFront(gitCommitWindow);
			}
		}
		
		private function onGitCommitWindowClosed(event:CloseEvent):void
		{
			if (gitCommitWindow.isSubmit) processManager.commit(gitCommitWindow.commitDiffCollection);
			
			gitCommitWindow.removeEventListener(CloseEvent.CLOSE, onGitCommitWindowClosed);
			PopUpManager.removePopUp(gitCommitWindow);
			gitCommitWindow = null;
		}
		
		private function onGitDiffChecked(event:GeneralEvent):void
		{
			processManager.removeEventListener(GitProcessManager.GIT_DIFF_CHECKED, onGitDiffChecked);
			if (gitCommitWindow) gitCommitWindow.commitDiffCollection = event.value as ArrayCollection;
		}
		
		private function onPullRequest(event:Event):void
		{
			
		}
		
		private function onPushRequest(event:Event):void
		{
			if (!ConstantsCoreVO.IS_MACOS)
			{
				if (!gitAuthWindow)
				{
					if (!checkOSXGitAccess()) return;
					
					processManager.checkGitAvailability();
					
					gitAuthWindow = PopUpManager.createPopUp(FlexGlobals.topLevelApplication as DisplayObject, GitAuthenticationPopup, false) as GitAuthenticationPopup;
					gitAuthWindow.title = "Git Needs Authentication";
					gitAuthWindow.isGitAvailable = isGitAvailable;
					gitAuthWindow.addEventListener(CloseEvent.CLOSE, onGitAuthWindowClosed);
					PopUpManager.centerPopUp(gitAuthWindow);
				}
				else
				{
					PopUpManager.bringToFront(gitAuthWindow);
				}
			}
			else
			{
				processManager.push();
			}
		}
		
		private function onGitAuthWindowClosed(event:CloseEvent):void
		{
			if (gitAuthWindow.userObject) processManager.push(gitAuthWindow.userObject);
			
			gitAuthWindow.removeEventListener(CloseEvent.CLOSE, onGitAuthWindowClosed);
			PopUpManager.removePopUp(gitAuthWindow);
			gitAuthWindow = null;
		}
		
		private function onRefreshRequest(event:Event):void
		{
			
		}
		
		private function onNewBranchRequest(event:Event):void
		{
			
		}
		
		private function onChangeBranchRequest(event:Event):void
		{
			
		}
		
		private function onMenuTypeUpdateAgainstGit(event:ProjectEvent):void
		{
			processManager.checkIfGitRepository(event.project as AS3ProjectVO);
			if (!processManager.hasEventListener(GitProcessManager.GIT_REPOSITORY_TEST))
				processManager.addEventListener(GitProcessManager.GIT_REPOSITORY_TEST, onGitRepositoryTested, false, 0, true);
		}
		
		private function onGitRepositoryTested(event:GeneralEvent):void
		{
			processManager.removeEventListener(GitProcessManager.GIT_REPOSITORY_TEST, onGitRepositoryTested);
			if (event.value && !gitRepositoryPermissionWindow)
			{
				gitRepositoryPermissionWindow = new GitRepositoryPermissionPopup;
				gitRepositoryPermissionWindow.project = event.value.project;
				gitRepositoryPermissionWindow.gitRootLocation = event.value.gitRootLocation;
				gitRepositoryPermissionWindow.horizontalCenter = gitRepositoryPermissionWindow.verticalCenter = 0;
				gitRepositoryPermissionWindow.addEventListener(Event.CLOSE, onGitRepositoryPermissionClosed, false, 0, true);
				FlexGlobals.topLevelApplication.addElement(gitRepositoryPermissionWindow);
			}
		}
		
		private function onGitRepositoryPermissionClosed(event:Event):void
		{
			gitRepositoryPermissionWindow.removeEventListener(Event.CLOSE, onGitRepositoryPermissionClosed);
			
			if (gitRepositoryPermissionWindow.isAccepted) gitRepositoryPermissionWindow.project.menuType += ","+ ProjectMenuTypes.GIT_PROJECT;
			
			FlexGlobals.topLevelApplication.removeElement(gitRepositoryPermissionWindow);
			gitRepositoryPermissionWindow = null;
			
			checkOSXGitAccess();
		}
	}
}