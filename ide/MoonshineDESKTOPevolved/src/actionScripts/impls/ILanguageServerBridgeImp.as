package actionScripts.impls
{
	import actionScripts.interfaces.ILanguageServerBridge;
	import flash.errors.IllegalOperationError;
	import actionScripts.valueObjects.ProjectVO;
	import actionScripts.events.GlobalEventDispatcher;
	import actionScripts.languageServer.ILanguageServerManager;
	import actionScripts.events.ProjectEvent;
	import flash.events.Event;
	import actionScripts.plugin.actionscript.as3project.vo.AS3ProjectVO;
	import actionScripts.languageServer.ActionScriptLanguageServerManager;
	import actionScripts.plugin.java.javaproject.vo.JavaProjectVO;
	import actionScripts.languageServer.JavaLanguageServerManager;

	public class ILanguageServerBridgeImp implements ILanguageServerBridge
	{
		public function ILanguageServerBridgeImp()
		{
			
		}

		private var _started:Boolean = false;
		private var dispatcher:GlobalEventDispatcher = GlobalEventDispatcher.getInstance();
		private var managers:Vector.<ILanguageServerManager> = new <ILanguageServerManager>[];
		private var managersWaitingForClose:Vector.<ILanguageServerManager> = new <ILanguageServerManager>[];

		public function get connectedProjectCount():int
		{
			if(!this._started)
			{
				return 0;
			}
			return managers.length + managersWaitingForClose.length;
		}
		
		public function start():void
		{
			if(this._started)
			{
				return;
			}
			this._started = true;
			dispatcher.addEventListener(ProjectEvent.ADD_PROJECT, addProjectHandler);
			dispatcher.addEventListener(ProjectEvent.REMOVE_PROJECT, removeProjectHandler);
			dispatcher.addEventListener(ProjectEvent.REMOVE_PROJECT, removeProjectHandler);
		}
		
		public function hasLanguageServerForProject(project:ProjectVO):Boolean
		{
			if(!this._started)
			{
				return false;
			}
			var serverCount:int = managers.length;
			for(var i:int = 0; i < serverCount; i++)
			{
				var manager:ILanguageServerManager = managers[i];
				if(manager.project == project)
				{
					return true;
				}
			}
			return false;
		}
		
		private function removeProjectHandler(event:ProjectEvent):void
		{
			var project:ProjectVO = event.project as ProjectVO;
			var managerCount:int = managers.length;
			for(var i:int = 0; i < managerCount; i++)
			{
				var manager:ILanguageServerManager = managers[i];
				if(manager.project === project)
				{
					managers.splice(i, 1);
					managersWaitingForClose.push(manager);
					manager.addEventListener(Event.CLOSE, manager_closeHandler);
					break;
				}
			}
		}
		
		private function addProjectHandler(event:ProjectEvent):void
		{
			var project:ProjectVO = event.project;
			if(!project || project.projectFolder.projectReference.isTemplate || hasLanguageServerForProject(project))
			{
				return;
			}
			if(project is AS3ProjectVO)
			{
				var as3Project:AS3ProjectVO = AS3ProjectVO(project);
				if(as3Project.isVisualEditorProject)
				{
					//Moonshine sometimes dispatches ProjectEvent.ADD_PROJECT for
					//projects that have already been added
					return;
				}
				var as3Manager:ActionScriptLanguageServerManager = new ActionScriptLanguageServerManager(as3Project);
				managers.push(as3Manager);
			}
			if(project is JavaProjectVO)
			{
				var javaProject:JavaProjectVO = JavaProjectVO(project);
				var javaManager:JavaLanguageServerManager = new JavaLanguageServerManager(javaProject);
				managers.push(javaManager);
			}
		}

		private function manager_closeHandler(event:Event):void
		{
			var manager:ILanguageServerManager = ILanguageServerManager(event.currentTarget);
			var index:int = managersWaitingForClose.indexOf(manager);
			managersWaitingForClose.splice(index, 1);
			dispatcher.dispatchEvent(new ProjectEvent(ProjectEvent.LANGUAGE_SERVER_CLOSED, manager.project));
		}
	}
}