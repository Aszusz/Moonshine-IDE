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
package actionScripts.controllers
{
    import actionScripts.ui.editor.BasicTextEditor;

    import flash.display.DisplayObject;
    import flash.events.Event;
    import flash.events.MouseEvent;
    
    import mx.collections.ArrayCollection;
    import mx.core.FlexGlobals;
    import mx.events.ResizeEvent;
    import mx.managers.PopUpManager;

    import spark.components.Button;
    
    import actionScripts.events.GlobalEventDispatcher;
    import actionScripts.locator.IDEModel;
    import actionScripts.ui.IContentWindow;
    import actionScripts.ui.menu.MenuPlugin;
    import actionScripts.ui.tabview.CloseTabEvent;
    import actionScripts.ui.tabview.TabView;
    import actionScripts.utils.UtilsCore;
    import actionScripts.valueObjects.ConstantsCoreVO;
    import actionScripts.valueObjects.HamburgerMenuTabsVO;
    
    import components.popup.StandardPopup;

	public class CloseTabCommand implements ICommand
	{
		private var model:IDEModel = IDEModel.getInstance();
		private var dispatcher:GlobalEventDispatcher = GlobalEventDispatcher.getInstance();
		
		private var tabToClose:IContentWindow;
		private var pop:StandardPopup;

		public function execute(event:Event):void
		{
			if (event.type == CloseTabEvent.EVENT_CLOSE_ALL_TABS)
			{
                var tabView:TabView = model.mainView.mainContent;
				if (tabView)
				{
					tabView.removeTabsFromCache();
				}
				UtilsCore.closeAllRelativeEditors(null);
				return;
			}
			
			if (event.hasOwnProperty('tab'))
				tabToClose = event['tab'];
			else
				tabToClose = model.activeEditor;	
			
			var forceClose:Boolean;
			if (event.hasOwnProperty('forceClose'))
				forceClose = event['forceClose'];

			if (!forceClose && tabToClose.isChanged())
			{	
				pop = new StandardPopup();
				pop.data = this; // Keep the command from getting GC'd
				pop.text = tabToClose.label + " is changed.";
				
				// Changed tabs are marked with * before the filename. Strip if found.
				if (pop.text.charAt(0) == "*")
				{
					pop.text = pop.text.substr(1);
				}
				
				var save:Button = new Button();
				save.styleName = "lightButton";
				save.label = "Save file";
				save.addEventListener(MouseEvent.CLICK, saveTab, false, 0, false);
				
				var close:Button = new Button();
				close.styleName = "lightButton";
				close.label = "Discard";
				close.addEventListener(MouseEvent.CLICK, closeTab, false, 0, false);
				
				var cancel:Button = new Button();
				cancel.styleName = "lightButton";
				cancel.label = "See file again";
				cancel.addEventListener(MouseEvent.CLICK, seeFileAgain, false, 0, false);
				 
				pop.buttons = [save, close, cancel];
				
				PopUpManager.addPopUp(pop, FlexGlobals.topLevelApplication as DisplayObject, true);
				pop.y = (ConstantsCoreVO.IS_MACOS) ? 25 : 45;
				pop.x = (FlexGlobals.topLevelApplication.width-pop.width)/2;
				
				model.isIndividualCloseTabAlertShowing = true;
				
				// @devsena
				// we need this because if application frame resized when above alert
				// opened, the alert didn't make it's position at center of the application but static
				FlexGlobals.topLevelApplication.addEventListener(ResizeEvent.RESIZE, onApplicationResized);
				
				// @devsena
				// if quitCommand ask this to close, then close it
				dispatcher.addEventListener(CloseTabEvent.EVENT_DISMISS_INDIVIDUAL_TAB_CLOSE_ALERT, onForceCloseRequest);
				// disable file menus in OSX
				dispatcher.dispatchEvent(new Event(MenuPlugin.CHANGE_MENU_MAC_NO_MENU_STATE));
			}
			else
			{
				closeTab();
			}
			
		}
		
		private function cleanUp():void
		{
			if (pop)
			{
				FlexGlobals.topLevelApplication.removeEventListener(ResizeEvent.RESIZE, onApplicationResized);
				dispatcher.removeEventListener(CloseTabEvent.EVENT_DISMISS_INDIVIDUAL_TAB_CLOSE_ALERT, onForceCloseRequest);
				dispatcher.dispatchEvent(new Event(MenuPlugin.CHANGE_MENU_MAC_ENABLE_STATE));
				PopUpManager.removePopUp(pop);
				pop.data = null;
				pop = null;
				model.isIndividualCloseTabAlertShowing = false;
			}
			
			tabToClose = null;
		}
		
		private function onApplicationResized(event:ResizeEvent):void
		{
			if (pop) pop.x = (FlexGlobals.topLevelApplication.width-pop.width)/2;
		}
		
		private function onForceCloseRequest(event:Event):void
		{
			if (pop) cleanUp();
		}
		
		private function seeFileAgain(event:Event=null):void
		{
            if (tabToClose is BasicTextEditor)
            {
                model.mainView.mainContent.setSelectedTab(tabToClose as DisplayObject);
            }
			cleanUp();
		}
		
		private function saveTab(event:Event=null):void
		{
			tabToClose.save();
			closeTab();
			
			cleanUp();
		}
		
		private function closeTab(event:Event=null):void
		{
			//if (tabToClose is TourDeTextEditor) TourDeTextEditor(tabToClose).disposeFootprint();
			model.removeEditor(tabToClose);
			
			// Notify everyone we closed the tab
			dispatcher.dispatchEvent(
				new CloseTabEvent(CloseTabEvent.EVENT_TAB_CLOSED, tabToClose as DisplayObject)
			);
			
			// Dispatch for the given tab as well (to reduce global listeners)
			tabToClose.dispatchEvent(
				new CloseTabEvent(CloseTabEvent.EVENT_TAB_CLOSED, tabToClose as DisplayObject)
			);

            var tabView:TabView = model.mainView.mainContent;
            if (tabView)
            {
                var hamburgerMenuTabs:ArrayCollection = tabView.model.hamburgerTabs;
                for (var i:int = 0; i < hamburgerMenuTabs.length; i++)
				{
					var item:HamburgerMenuTabsVO = hamburgerMenuTabs.getItemAt(i) as HamburgerMenuTabsVO;
					if (item.tabData == tabToClose)
					{
						hamburgerMenuTabs.removeItemAt(i);
						break;
					}
				}
            }

            cleanUp();
			
			// If we have a default tab that should be displayed, give it a shot now
			if (model.editors.length == 0)
			{
				dispatcher.dispatchEvent(
					new CloseTabEvent(CloseTabEvent.EVENT_ALL_TABS_CLOSED, null)
				);
			}
		}
	}
}