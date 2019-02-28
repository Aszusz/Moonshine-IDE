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
package actionScripts.plugins.startup
{
    import flash.events.Event;
    import flash.utils.clearTimeout;
    import flash.utils.setTimeout;
    
    import mx.core.FlexGlobals;
    
    import actionScripts.events.AddTabEvent;
    import actionScripts.events.GlobalEventDispatcher;
    import actionScripts.events.ProjectEvent;
    import actionScripts.events.StartupHelperEvent;
    import actionScripts.factory.FileLocation;
    import actionScripts.impls.IHelperMoonshineBridgeImp;
    import actionScripts.plugin.IPlugin;
    import actionScripts.plugin.PluginBase;
    import actionScripts.plugin.actionscript.as3project.vo.AS3ProjectVO;
    import actionScripts.plugin.settings.SettingsView;
    import actionScripts.ui.IContentWindow;
    import actionScripts.ui.menu.MenuPlugin;
    import actionScripts.ui.tabview.CloseTabEvent;
    import actionScripts.utils.EnvironmentUtils;
    import actionScripts.utils.PathSetupHelperUtil;
    import actionScripts.valueObjects.ConstantsCoreVO;
    import actionScripts.valueObjects.ProjectVO;
    import actionScripts.valueObjects.SDKTypes;
    
    import components.popup.GettingStartedPopup;
    import components.popup.JavaPathSetupPopup;
    import components.popup.SDKUnzipConfirmPopup;

	public class StartupHelperPlugin extends PluginBase implements IPlugin
	{
		override public function get name():String			{ return "Startup Helper Plugin"; }
		override public function get author():String		{ return "Moonshine Project Team"; }
		override public function get description():String	{ return "Startup Helper Plugin. Esc exits."; }
		
		public static const EVENT_GETTING_STARTED:String = "gettingStarted";
		
		private static const SDK_XTENDED:String = "SDK_XTENDED";
		private static const CC_JAVA:String = "CC_JAVA";
		private static const CC_SDK:String = "CC_SDK";
		private static const CC_ANT:String = "CC_ANT";
		private static const CC_MAVEN:String = "CC_MAVEN";
		
		private var dependencyCheckUtil:IHelperMoonshineBridgeImp = new IHelperMoonshineBridgeImp();
		private var sdkNotificationView:SDKUnzipConfirmPopup;
		private var ccNotificationView:JavaPathSetupPopup;
		private var gettingStartedPopup:GettingStartedPopup;
		private var environmentUtil:EnvironmentUtils = new EnvironmentUtils();
		private var sequences:Array;
		private var sequenceIndex:int = 0;
		private var isSDKSetupShowing:Boolean;

		private var javaSetupPathTimeout:uint;
		private var startHelpingTimeout:uint;
		private var changeMenuSDKTimeout:uint;
		private var didShowPreviouslyOpenedTabs:Boolean;
		
		private var _isAllDependenciesPresent:Boolean = true;
		private function set isAllDependenciesPresent(value:Boolean):void
		{
			_isAllDependenciesPresent = value;
			if (!_isAllDependenciesPresent)
			{
				// dispatch event to open Getting Started tab
				onGettingStartedRequest(null);
			}
		}
		private function get isAllDependenciesPresent():Boolean
		{
			return _isAllDependenciesPresent;
		}
		
		/**
		 * INITIATOR
		 */
		override public function activate():void
		{
			super.activate();
			
			// we want this to be work in desktop version only
			if (!ConstantsCoreVO.IS_AIR) return;
			
			dispatcher.addEventListener(StartupHelperEvent.EVENT_RESTART_HELPING, onRestartRequest, false, 0, true);
			dispatcher.addEventListener(EVENT_GETTING_STARTED, onGettingStartedRequest, false, 0, true);
			
			// event listner to open up #sdk-extended from File in OSX
			CONFIG::OSX
			{
				dispatcher.addEventListener(StartupHelperEvent.EVENT_SDK_SETUP_REQUEST, onSDKSetupRequest, false, 0, true);
				dispatcher.addEventListener(StartupHelperEvent.EVENT_MOONSHINE_HELPER_DOWNLOAD_REQUEST, onMoonshineHelperDownloadRequest, false, 0, true);
			}
			
			preInitHelping();
		}
		
		/**
		 * Pre-initialization helping process
		 */
		private function preInitHelping():void
		{
			sequences = [SDK_XTENDED, CC_JAVA, CC_SDK, CC_ANT, CC_MAVEN];

			// just a little delay to see things visually right
			environmentUtil.readValues();
            startHelpingTimeout = setTimeout(startHelping, 1000);
			copyToLocalStoragePayaraEmbededLauncher();
		}

		/**
		 * Starts the checks and starup sequences
		 * to setup SDK, Java etc.
		 */
		private function startHelping():void
		{
			clearTimeout(startHelpingTimeout);
			startHelpingTimeout = 0;

			var tmpSequence:String = sequences[sequenceIndex];
			
			switch(tmpSequence)
			{
				case SDK_XTENDED:
				{
					checkDefaultSDK();
					break;
				}
				case CC_JAVA:
				{
					checkJavaPathPresenceForTypeahead();
					break;
				}
				case CC_SDK:
				{
					checkSDKPrsenceForTypeahead();
					break;
				}
				case CC_ANT:
				{
					checkAntPathPresence();
					break;
				}
				case CC_MAVEN:
				{
					checkMavenPathPresence();
					break;
				}
			}

			if (!didShowPreviouslyOpenedTabs)
			{
                didShowPreviouslyOpenedTabs = true;
				var timeoutValue:uint = setTimeout(function():void
				{
					clearTimeout(timeoutValue);
					dispatcher.dispatchEvent(new ProjectEvent(ProjectEvent.SHOW_PREVIOUSLY_OPENED_PROJECTS));
				}, 2000);
			}
		}
		
		/**
		 * Checks default SDK to Moonshine
		 */
		private function checkDefaultSDK(forceShow:Boolean=false):void
		{
			sequenceIndex++;
			
			var isPresent:Boolean = dependencyCheckUtil.isDefaultSDKPresent();
			if (!isPresent && (!ConstantsCoreVO.IS_MACOS || (ConstantsCoreVO.IS_MACOS && (!ConstantsCoreVO.IS_SDK_HELPER_PROMPT_DNS || forceShow))))
			{
				//triggerSDKNotificationView(false, false);
				
				// check if env.variable has any FLEX_HOME found or not
				if (environmentUtil.environments.FLEX_HOME)
				{
					// set as default SDK
					PathSetupHelperUtil.updateFieldPath(SDKTypes.FLEX, environmentUtil.environments.FLEX_HOME.path.nativePath);
					startHelping();
				}
				else
				{
					isAllDependenciesPresent = false;
				}
			}
			else if (isPresent)
			{
				// restart rest of the checkings
				startHelping();
			}
			else if (!isPresent)
			{
				// lets show up the default sdk requirement strip at bottom
                changeMenuSDKTimeout = setTimeout(function():void
				{
					clearTimeout(changeMenuSDKTimeout);
                    changeMenuSDKTimeout = 0;
					
					dispatcher.dispatchEvent(new Event(MenuPlugin.CHANGE_MENU_SDK_STATE));
				}, 1000);
			}
		}
		
		/**
		 * Checks code-completion Java presence
		 */
		private function checkJavaPathPresenceForTypeahead():void
		{
			sequenceIndex++;
			
			var isPresent:Boolean = dependencyCheckUtil.isJavaPresent();
			if (!isPresent && !ccNotificationView)
			{
				// check if env.variable has JAVA_HOME with JDK setup
				if (environmentUtil.environments.JAVA_HOME)
				{
					PathSetupHelperUtil.updateFieldPath(SDKTypes.OPENJAVA, environmentUtil.environments.JAVA_HOME.nativePath);
					startHelping();
				}
				else
				{
					isAllDependenciesPresent = false;
					model.javaPathForTypeAhead = null;
				}
                //javaSetupPathTimeout = setTimeout(triggerJavaSetupViewWithParam, 1000, false);
			}
			else
			{
				// restart rest of the checkings
				startHelping();
			}
		}
		
		/**
		 * Checks code-completion sdk requisites
		 */
		private function checkSDKPrsenceForTypeahead():void
		{
			sequenceIndex++;
			
			var isPresent:Boolean = dependencyCheckUtil.isDefaultSDKPresent();
			//var path:String = UtilsCore.checkCodeCompletionFlexJSSDK();
			if (!isPresent && !ccNotificationView && !isSDKSetupShowing)
			{
				if (environmentUtil.environments.JAVA_HOME)
				{
					PathSetupHelperUtil.updateFieldPath(SDKTypes.OPENJAVA, environmentUtil.environments.JAVA_HOME.nativePath);
					startHelping();
				}
				else
				{
					isAllDependenciesPresent = false;
				}
                //javaSetupPathTimeout = setTimeout(triggerJavaSetupViewWithParam, 1000, true);
			}
			else if (!isPresent && isSDKSetupShowing)
			{
				isAllDependenciesPresent = false;
				showNoSDKStripAndListenForDefaultSDK();
			}
			else if (isPresent && dependencyCheckUtil.isJavaPresent())
			{
				// starting server
				model.languageServerCore.start();
				dispatcher.addEventListener(StartupHelperEvent.EVENT_TYPEAHEAD_REQUIRES_SDK, onTypeaheadFailedDueToSDK);
				
				// check if any projects already opened 
				// so we can start servers against them as well
				for each (var i:ProjectVO in model.projects)
				{
					// we don't run server on visual editor projects
					if (!(i as AS3ProjectVO).isVisualEditorProject)
					{
						dispatcher.dispatchEvent(new ProjectEvent(ProjectEvent.START_LANGUAGE_SERVER_ON_OPENED_PROJECT, i));
					}
				}
				
				startHelping();
			}
		}
		
		/**
		 * Checks internal Ant path
		 */
		private function checkAntPathPresence():void
		{
			sequenceIndex++;
			
			var isPresent:Boolean = dependencyCheckUtil.isAntPresent();
			if (!isPresent)
			{
				if (environmentUtil.environments.ANT_HOME)
				{
					PathSetupHelperUtil.updateFieldPath(SDKTypes.ANT, environmentUtil.environments.ANT_HOME.nativePath);
					startHelping();
				}
				else
				{
					isAllDependenciesPresent = false;
				}
			}
			else
			{
				startHelping();
			}
		}
		
		/**
		 * Checks internal Maven path
		 */
		private function checkMavenPathPresence():void
		{
			sequenceIndex++;
			
			var isPresent:Boolean = dependencyCheckUtil.isMavenPresent();
			if (!model.mavenPath || model.mavenPath == "")
			{
				if (environmentUtil.environments.MAVEN_HOME)
				{
					PathSetupHelperUtil.updateFieldPath(SDKTypes.MAVEN, environmentUtil.environments.MAVEN_HOME.nativePath);
				}
				else
				{
					isAllDependenciesPresent = false;
				}
			}
		}
		
		/**
		 * Opening SDK notification prompt
		 */
		private function triggerSDKNotificationView(showAsDownloader:Boolean, showAsRequiresSDKNotif:Boolean):void
		{
			sdkNotificationView = new SDKUnzipConfirmPopup;
			sdkNotificationView.showAsHelperDownloader = showAsDownloader;
			sdkNotificationView.horizontalCenter = sdkNotificationView.verticalCenter = 0;
			sdkNotificationView.addEventListener(Event.CLOSE, onSDKNotificationClosed, false, 0, true);
			FlexGlobals.topLevelApplication.addElement(sdkNotificationView);
		}
		
		/**
		 * Opens Java detection etc. for code-completion prompt
		 */
		private function triggerJavaSetupViewWithParam(showAsRequiresSDKNotif:Boolean):void
		{
			clearTimeout(javaSetupPathTimeout);
			javaSetupPathTimeout = 0;
			
			ccNotificationView = new JavaPathSetupPopup();
			ccNotificationView.showAsRequiresSDKNotification = showAsRequiresSDKNotif;
			ccNotificationView.horizontalCenter = ccNotificationView.verticalCenter = 0;
			ccNotificationView.addEventListener(Event.CLOSE, onJavaPromptClosed, false, 0, true);
			FlexGlobals.topLevelApplication.addElement(ccNotificationView);
		}
		
		/**
		 * Showing no sdk strip at bottom and also listens for
		 * default SDK setup event
		 */
		private function showNoSDKStripAndListenForDefaultSDK():void
		{
			// lets show up the default sdk requirement strip at bottom
			// at very end of startup prompt being shown
			dispatcher.dispatchEvent(new Event(MenuPlugin.CHANGE_MENU_SDK_STATE));
			// in case of Windows, we open-up MXMLC Plugin section and shall
			// wait for the user to add/download a default SDK
			sequenceIndex --;
			dispatcher.addEventListener(CloseTabEvent.EVENT_CLOSE_TAB, onSettingsTabClosed);
		}
		
		//--------------------------------------------------------------------------
		//
		//  LISTENERS API
		//
		//--------------------------------------------------------------------------
		
		/**
		 * To restart helping process
		 */
		private function onRestartRequest(event:StartupHelperEvent):void
		{
			sdkNotificationView = null;
			ccNotificationView = null;
			sequences = null;
			sequenceIndex = 0;
			isSDKSetupShowing = false;
			ConstantsCoreVO.IS_OSX_CODECOMPLETION_PROMPT = false;
			
			preInitHelping();
		}
		
		/**
		 * On getting started menu item
		 */
		private function onGettingStartedRequest(event:Event):void
		{
			if (!gettingStartedPopup)
			{
				gettingStartedPopup = new GettingStartedPopup;
				gettingStartedPopup.dependencyCheckUtil = dependencyCheckUtil;
				gettingStartedPopup.addEventListener(CloseTabEvent.EVENT_TAB_CLOSED, onGettingStartedClosed, false, 0, true);
			}
			
			GlobalEventDispatcher.getInstance().dispatchEvent(
				new AddTabEvent(gettingStartedPopup as IContentWindow)
			);
		}
		
		/**
		 * On getting started closed
		 */
		private function onGettingStartedClosed(event:Event):void
		{
			gettingStartedPopup.removeEventListener(CloseTabEvent.EVENT_TAB_CLOSED, onGettingStartedClosed);
			gettingStartedPopup = null;
		}
		
		/**
		 * On SDK notification prompt close
		 */
		private function onSDKNotificationClosed(event:Event):void
		{
			var wasShowingAsHelperDownloaderOnly:Boolean = sdkNotificationView.showAsHelperDownloader;
			
			sdkNotificationView.removeEventListener(Event.CLOSE, onSDKNotificationClosed);
			FlexGlobals.topLevelApplication.removeElement(sdkNotificationView);
			
			var isSDKSetupSectionOpened:Boolean = sdkNotificationView.isSDKSetupSectionOpened;
			sdkNotificationView = null;
			
			if (wasShowingAsHelperDownloaderOnly) return;
			
			// restart rest of the checkings
			if (!isSDKSetupSectionOpened) startHelping();
			else 
			{
				// in case of Windows, we open-up MXMLC Plugin section and shall
				// wait for the user to add/download a default SDK
				dispatcher.addEventListener(CloseTabEvent.EVENT_CLOSE_TAB, onSettingsTabClosed);
			}
		}
		
		/**
		 * On code-completion Java prompt close
		 */
		private function onJavaPromptClosed(event:Event):void
		{
			ccNotificationView.removeEventListener(Event.CLOSE, onJavaPromptClosed);
			FlexGlobals.topLevelApplication.removeElement(ccNotificationView);
			
			var isDiscardedCodeCompletionProcedure:Boolean = ccNotificationView.isDiscarded;
			var showAsRequiresSDKNotif:Boolean = ccNotificationView.showAsRequiresSDKNotification;
			isSDKSetupShowing = ccNotificationView.isSDKSetupShowing;
			ccNotificationView = null;
			
			// restart rest of the checkings
			if (!isDiscardedCodeCompletionProcedure) startHelping();
			else if (!model.defaultSDK && (isDiscardedCodeCompletionProcedure || showAsRequiresSDKNotif))
			{
				showNoSDKStripAndListenForDefaultSDK();
			}
		}

		/**
		 * During code-completion server started and
		 * required SDK removed from SDK list
		 */
		private function onTypeaheadFailedDueToSDK(event:StartupHelperEvent):void
		{
			triggerJavaSetupViewWithParam(true);
		}
		
		/**
		 * When settings tab closed after default SDK setup
		 * done in Windows process
		 */
		private function onSettingsTabClosed(event:Event):void
		{
			if (event is CloseTabEvent)
			{
				var tmpEvent:CloseTabEvent = event as CloseTabEvent;
				if ((tmpEvent.tab is SettingsView) && (SettingsView(tmpEvent.tab).longLabel == "Settings") && SettingsView(tmpEvent.tab).isSaved)
				{
					dispatcher.removeEventListener(CloseTabEvent.EVENT_CLOSE_TAB, onSettingsTabClosed);
					startHelping();
				}
			}
		}
		
		/**
		 * On helper application download requrest from File menu
		 * in OSX
		 */
		private function onSDKSetupRequest(event:StartupHelperEvent):void
		{
			sequenceIndex = 0;
			checkDefaultSDK(true);
		}
		
		/**
		 * On Moonshine App Store Helper request from top menu
		 */
		private function onMoonshineHelperDownloadRequest(event:Event):void
		{
			triggerSDKNotificationView(true, false);
		}

        private function copyToLocalStoragePayaraEmbededLauncher():void
        {
			var payaraLocation:String = "elements".concat(model.fileCore.separator, "projects", model.fileCore.separator, "PayaraEmbeddedLauncher");
            var payaraAppPath:FileLocation = model.fileCore.resolveApplicationDirectoryPath(payaraLocation);
            model.payaraServerLocation = model.fileCore.resolveApplicationStorageDirectoryPath("projects".concat(model.fileCore.separator, "PayaraEmbeddedLauncher"));
            try
            {
                payaraAppPath.fileBridge.copyTo(model.payaraServerLocation, true);
            }
			catch (e:Error)
			{
				warning("Problem with updating PayaraEmbeddedLauncher %s", e.message);
			}
        }
    }
}