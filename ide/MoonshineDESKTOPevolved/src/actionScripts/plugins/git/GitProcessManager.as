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
package actionScripts.plugins.git
{
	import com.adobe.utils.StringUtil;
	
	import flash.filesystem.File;
	
	import mx.collections.ArrayCollection;
	
	import actionScripts.events.GeneralEvent;
	import actionScripts.events.GlobalEventDispatcher;
	import actionScripts.events.ProjectEvent;
	import actionScripts.events.StatusBarEvent;
	import actionScripts.events.WorkerEvent;
	import actionScripts.factory.FileLocation;
	import actionScripts.locator.IDEModel;
	import actionScripts.locator.IDEWorker;
	import actionScripts.plugin.actionscript.as3project.vo.AS3ProjectVO;
	import actionScripts.plugin.console.ConsoleOutputter;
	import actionScripts.plugins.git.model.GitProjectVO;
	import actionScripts.plugins.git.model.MethodDescriptor;
	import actionScripts.ui.menu.vo.ProjectMenuTypes;
	import actionScripts.valueObjects.ConstantsCoreVO;
	import actionScripts.valueObjects.GenericSelectableObject;
	import actionScripts.valueObjects.WorkerNativeProcessResult;
	import actionScripts.vo.NativeProcessQueueVO;
	
	public class GitProcessManager extends ConsoleOutputter
	{
		public static const GIT_DIFF_CHECKED:String = "gitDiffProcessCompleted";
		public static const GIT_REPOSITORY_TEST:String = "checkIfGitRepository";
		public static const GIT_STATUS_FILE_MODIFIED:String = "gitStatusFileModified";
		public static const GIT_STATUS_FILE_DELETED:String = "gitStatusFileDeleted";
		public static const GIT_STATUS_FILE_NEW:String = "gitStatusFileNew";
		public static const GIT_REMOTE_BRANCH_LIST:String = "getGitRemoteBranchList";
		
		private static const XCODE_PATH_DECTECTION:String = "xcodePathDectection";
		private static const GIT_AVAIL_DECTECTION:String = "gitAvailableDectection";
		private static const GIT_DIFF_CHECK:String = "checkGitDiff";
		private static const GIT_PUSH:String = "gitPush";
		private static const GIT_REMOTE_ORIGIN_URL:String = "getGitRemoteURL";
		private static const GIT_CURRENT_BRANCH_NAME:String = "getGitCurrentBranchName";
		private static const GIT_COMMIT:String = "gitCommit";
		private static const GIT_CHECKOUT_BRANCH:String = "gitCheckoutToBranch";
		private static const GIT_CHECKOUT_NEW_BRANCH:String = "gitCheckoutNewBranch";
		
		public var gitBinaryPathOSX:String;
		public var setGitAvailable:Function;
		public var plugin:GitHubPlugin;
		public var pendingProcess:Array /* of MethodDescriptor */ = [];
		
		protected var processType:String;
		
		private var worker:IDEWorker = IDEWorker.getInstance();
		private var queue:Vector.<Object> = new Vector.<Object>();
		private var model:IDEModel = IDEModel.getInstance();
		private var isErrorClose:Boolean;
		private var onXCodePathDetection:Function;
		private var gitTestProject:AS3ProjectVO;
		private var dispatcher:GlobalEventDispatcher = GlobalEventDispatcher.getInstance();
		private var lastCloneURL:String;
		
		private var _cloningProjectName:String;
		private function get cloningProjectName():String
		{
			return _cloningProjectName;
		}
		private function set cloningProjectName(value:String):void
		{
			var quoteIndex:int = value.indexOf("'");
			_cloningProjectName = value.substring(++quoteIndex, value.indexOf("'", quoteIndex));
		}
		
		public function GitProcessManager()
		{
			worker.sendToWorker(WorkerEvent.SET_IS_MACOS, ConstantsCoreVO.IS_MACOS);
			worker.addEventListener(IDEWorker.WORKER_VALUE_INCOMING, onWorkerValueIncoming, false, 0, true);
		}
		
		public function getOSXCodePath(completion:Function):void
		{
			queue = new Vector.<Object>();
			
			addToQueue(new NativeProcessQueueVO('xcode-select -p', false, XCODE_PATH_DECTECTION));
			worker.sendToWorker(WorkerEvent.RUN_LIST_OF_NATIVEPROCESS, {queue:queue, workingDirectory:null});
		}
		
		public function checkGitAvailability():void
		{
			queue = new Vector.<Object>();
			
			addToQueue(new NativeProcessQueueVO(ConstantsCoreVO.IS_MACOS ? gitBinaryPathOSX +' --version' : 'git&&--version', false, GIT_AVAIL_DECTECTION));
			worker.sendToWorker(WorkerEvent.RUN_LIST_OF_NATIVEPROCESS, {queue:queue, workingDirectory:null});
		}
		
		public function checkIfGitRepository(project:AS3ProjectVO):void
		{
			queue = new Vector.<Object>();
			gitTestProject = project;
			
			addToQueue(new NativeProcessQueueVO(ConstantsCoreVO.IS_MACOS ? gitBinaryPathOSX +' rev-parse --git-dir' : 'git&&rev-parse&&--git-dir', false, GIT_REPOSITORY_TEST));
			worker.sendToWorker(WorkerEvent.RUN_LIST_OF_NATIVEPROCESS, {queue:queue, workingDirectory:project.folderLocation.fileBridge.nativePath});
		}
		
		public function getGitRemoteURL():void
		{
			queue = new Vector.<Object>();
			gitTestProject = model.activeProject as AS3ProjectVO;

			addToQueue(new NativeProcessQueueVO(ConstantsCoreVO.IS_MACOS ? gitBinaryPathOSX +' config --get remote.origin.url' : 'git&&config&&--get&&remote.origin.url', false, GIT_REMOTE_ORIGIN_URL));
			worker.sendToWorker(WorkerEvent.RUN_LIST_OF_NATIVEPROCESS, {queue:queue, workingDirectory:model.activeProject.folderLocation.fileBridge.nativePath});
		}
		
		public function getCurrentBranch():void
		{
			if (!model.activeProject) return;
			
			queue = new Vector.<Object>();
			
			addToQueue(new NativeProcessQueueVO(ConstantsCoreVO.IS_MACOS ? gitBinaryPathOSX +' branch' : 'git&&branch', false, GIT_CURRENT_BRANCH_NAME));
			worker.sendToWorker(WorkerEvent.RUN_LIST_OF_NATIVEPROCESS, {queue:queue, workingDirectory:model.activeProject.folderLocation.fileBridge.nativePath});
		}
		
		public function clone(url:String, target:String):void
		{
			queue = new Vector.<Object>();
			
			lastCloneURL = url;
			addToQueue(new NativeProcessQueueVO(ConstantsCoreVO.IS_MACOS ? gitBinaryPathOSX +' clone --progress -v '+ url : 'git&&clone&&--progress&&-v&&'+ url, false, GitHubPlugin.CLONE_REQUEST));
			worker.sendToWorker(WorkerEvent.RUN_LIST_OF_NATIVEPROCESS, {queue:queue, workingDirectory:target});
		}
		
		public function checkDiff():void
		{
			if (!model.activeProject) return;
			queue = new Vector.<Object>();
			
			addToQueue(new NativeProcessQueueVO(ConstantsCoreVO.IS_MACOS ? gitBinaryPathOSX +' status --porcelain > "'+ File.applicationStorageDirectory.nativePath + File.separator +'commitDiff.txt"' : 
				'git&&status&&--porcelain&&>&&'+ File.applicationStorageDirectory.nativePath + File.separator +'commitDiff.txt', false, GIT_DIFF_CHECK));
			worker.sendToWorker(WorkerEvent.RUN_LIST_OF_NATIVEPROCESS, {queue:queue, workingDirectory:model.activeProject.folderLocation.fileBridge.nativePath});
		}
		
		public function commit(files:ArrayCollection, withMessage:String):void
		{
			if (!model.activeProject) return;

			queue = new Vector.<Object>();
			
			for each (var i:GenericSelectableObject in files)
			{
				if (i.isSelected) 
				{
					addToQueue(new NativeProcessQueueVO(ConstantsCoreVO.IS_MACOS ? gitBinaryPathOSX +' add '+ i.data.path : 'git&&add&&'+ i.data.path, false, GIT_COMMIT));
				}
			}
			
			addToQueue(new NativeProcessQueueVO(ConstantsCoreVO.IS_MACOS ? gitBinaryPathOSX +' commit -m "'+ withMessage +'"' : 'git&&commit&&-m&&"'+ withMessage +'"', false, GIT_COMMIT));
			
			dispatcher.dispatchEvent(new StatusBarEvent(StatusBarEvent.PROJECT_BUILD_STARTED, "Requested", "Commit ", false));
			worker.sendToWorker(WorkerEvent.RUN_LIST_OF_NATIVEPROCESS, {queue:queue, workingDirectory:model.activeProject.folderLocation.fileBridge.nativePath});
		}
		
		public function revert(files:ArrayCollection):void
		{
			if (!model.activeProject) return;
			
			queue = new Vector.<Object>();
			
			for each (var i:GenericSelectableObject in files)
			{
				if (i.isSelected) 
				{
					switch(i.data.status)
					{
						case GitProcessManager.GIT_STATUS_FILE_DELETED:
						case GitProcessManager.GIT_STATUS_FILE_MODIFIED:
							addToQueue(new NativeProcessQueueVO(ConstantsCoreVO.IS_MACOS ? gitBinaryPathOSX +' checkout '+ i.data.path : 'git&&checkout&&'+ i.data.path, false, GIT_CHECKOUT_BRANCH, i.data.path));
							break;
							
						case GitProcessManager.GIT_STATUS_FILE_NEW:
							addToQueue(new NativeProcessQueueVO(ConstantsCoreVO.IS_MACOS ? gitBinaryPathOSX +' reset '+ i.data.path : 'git&&reset&&'+ i.data.path, false, GIT_CHECKOUT_BRANCH, i.data.path));
							break;
					}
				}
			}
			
			dispatcher.dispatchEvent(new StatusBarEvent(StatusBarEvent.PROJECT_BUILD_STARTED, "Requested", "File Revert ", false));
			worker.sendToWorker(WorkerEvent.RUN_LIST_OF_NATIVEPROCESS, {queue:queue, workingDirectory:plugin.modelAgainstProject[model.activeProject].rootLocal.nativePath});
		}
		
		public function push(userObject:Object=null):void
		{
			if (!model.activeProject) return;
			
			// safe-check
			if (!ConstantsCoreVO.IS_MACOS && !userObject && !plugin.modelAgainstProject[model.activeProject].sessionUser)
			{
				error("Git requires to authenticate to Push");
				return;
			}
			
			var tmpModel:GitProjectVO = plugin.modelAgainstProject[model.activeProject];
			var userName:String;
			var password:String;
			
			if (!ConstantsCoreVO.IS_MACOS)
			{
				userName = tmpModel.sessionUser ? tmpModel.sessionUser : userObject.userName;
				password = tmpModel.sessionPassword ? tmpModel.sessionPassword : userObject.password;
			}
			
			queue = new Vector.<Object>();
			
			//git push https://user:pass@github.com/user/project.git
			addToQueue(new NativeProcessQueueVO(ConstantsCoreVO.IS_MACOS ? gitBinaryPathOSX +' push -v origin '+ tmpModel.currentBranch : 'git&&push&&https://'+ userName +':'+ password +'@'+ tmpModel.remoteURL +'.git&&'+ tmpModel.currentBranch, false, GIT_PUSH));

			warning("Git push requested...");
			dispatcher.dispatchEvent(new StatusBarEvent(StatusBarEvent.PROJECT_BUILD_STARTED, "Requested", "Push ", false));
			worker.sendToWorker(WorkerEvent.RUN_LIST_OF_NATIVEPROCESS, {queue:queue, workingDirectory:model.activeProject.folderLocation.fileBridge.nativePath});
		}
		
		public function pull():void
		{
			if (!model.activeProject) return;
			
			var tmpModel:GitProjectVO = plugin.modelAgainstProject[model.activeProject];
			queue = new Vector.<Object>();
			
			addToQueue(new NativeProcessQueueVO(ConstantsCoreVO.IS_MACOS ? gitBinaryPathOSX +' pull --progress -v --no-rebase origin '+ tmpModel.currentBranch : 'git&&pull&&--progress&&-v&&--no-rebase&&origin&&'+ tmpModel.currentBranch, false, GitHubPlugin.PULL_REQUEST));
			worker.sendToWorker(WorkerEvent.RUN_LIST_OF_NATIVEPROCESS, {queue:queue, workingDirectory:model.activeProject.folderLocation.fileBridge.nativePath});
		}
		
		public function switchBranch():void
		{
			if (!model.activeProject) return;
			
			queue = new Vector.<Object>();
			
			addToQueue(new NativeProcessQueueVO(ConstantsCoreVO.IS_MACOS ? gitBinaryPathOSX +' fetch' : 'git&&fetch', false, null));
			addToQueue(new NativeProcessQueueVO(ConstantsCoreVO.IS_MACOS ? gitBinaryPathOSX +' branch -r' : 'git&&branch&&-r', false, GIT_REMOTE_BRANCH_LIST));
			pendingProcess.push(new MethodDescriptor(this, 'getCurrentBranch')); // next method we need to fire when above done
			
			warning("Fetching branch details...");
			worker.sendToWorker(WorkerEvent.RUN_LIST_OF_NATIVEPROCESS, {queue:queue, workingDirectory:model.activeProject.folderLocation.fileBridge.nativePath});
		}
		
		public function changeBranchTo(value:GenericSelectableObject):void
		{
			if (!model.activeProject) return;
			
			queue = new Vector.<Object>();
			
			addToQueue(new NativeProcessQueueVO(ConstantsCoreVO.IS_MACOS ? gitBinaryPathOSX +' checkout '+ (value.data as String): 'git&&checkout&&'+ (value.data as String), false, GIT_CHECKOUT_BRANCH));
			pendingProcess.push(new MethodDescriptor(this, "getCurrentBranch"));
			
			notice("Trying to switch branch...");
			worker.sendToWorker(WorkerEvent.RUN_LIST_OF_NATIVEPROCESS, {queue:queue, workingDirectory:model.activeProject.folderLocation.fileBridge.nativePath});
		}
		
		public function createAndCheckoutNewBranch(name:String, pushToOrigin:Boolean, userObject:Object=null):void
		{
			if (!model.activeProject) return;
			
			// safe-check
			if (!ConstantsCoreVO.IS_MACOS && !userObject && !plugin.modelAgainstProject[model.activeProject].sessionUser)
			{
				error("Git requires to authenticate to Push");
				return;
			}
			
			var tmpModel:GitProjectVO = plugin.modelAgainstProject[model.activeProject];
			queue = new Vector.<Object>();
			
			// https://stackoverflow.com/questions/1519006/how-do-you-create-a-remote-git-branch
			addToQueue(new NativeProcessQueueVO(ConstantsCoreVO.IS_MACOS ? gitBinaryPathOSX +' checkout -b '+ name : 'git&&checkout&&-b&&'+ name, false, GIT_CHECKOUT_NEW_BRANCH));
			pendingProcess.push(new MethodDescriptor(this, "getCurrentBranch"));
			if (pushToOrigin) 
			{
				pendingProcess.push(new MethodDescriptor(this, 'push', ConstantsCoreVO.IS_MACOS ? null : {userName:tmpModel.sessionUser ? tmpModel.sessionUser : userObject.userName, password: tmpModel.sessionPassword ? tmpModel.sessionPassword : userObject.password})); // next method we need to fire when above done
			}
			
			notice("Trying to switch branch...");
			worker.sendToWorker(WorkerEvent.RUN_LIST_OF_NATIVEPROCESS, {queue:queue, workingDirectory:model.activeProject.folderLocation.fileBridge.nativePath});
		}
		
		public function checkout():void
		{
			if (!model.activeProject) return;
			
			var tmpModel:GitProjectVO = plugin.modelAgainstProject[model.activeProject];
			
			queue = new Vector.<Object>();
			
			addToQueue(new NativeProcessQueueVO(ConstantsCoreVO.IS_MACOS ? gitBinaryPathOSX +' checkout '+ tmpModel.currentBranch +' --' : 'git&&checkout&&'+ tmpModel.currentBranch +'&&--', false, GIT_CHECKOUT_BRANCH));
			worker.sendToWorker(WorkerEvent.RUN_LIST_OF_NATIVEPROCESS, {queue:queue, workingDirectory:model.activeProject.folderLocation.fileBridge.nativePath});
		}
		
		private function onWorkerValueIncoming(event:GeneralEvent):void
		{
			var tmpValue:Object = event.value.value;
			switch (event.value.event)
			{
				case WorkerEvent.RUN_NATIVEPROCESS_OUTPUT:
					if (tmpValue.type == WorkerNativeProcessResult.OUTPUT_TYPE_DATA) shellData(tmpValue);
					else if (tmpValue.type == WorkerNativeProcessResult.OUTPUT_TYPE_CLOSE) shellExit(tmpValue);
					else shellError(tmpValue);
					break;
				case WorkerEvent.RUN_LIST_OF_NATIVEPROCESS_PROCESS_TICK:
					if (queue.length != 0) queue.shift();
					processType = tmpValue.processType;
					shellTick(tmpValue);
					break;
				case WorkerEvent.RUN_LIST_OF_NATIVEPROCESS_ENDED:
					listOfProcessEnded();
					dispatcher.dispatchEvent(new StatusBarEvent(StatusBarEvent.PROJECT_BUILD_ENDED));
					// starts checking pending process here
					if (pendingProcess.length > 0)
					{
						var process:MethodDescriptor = pendingProcess.shift();
						process.callMethod();
					}
					break;
				case WorkerEvent.CONSOLE_MESSAGE_NATIVEPROCESS_OUTPUT:
					debug("%s", event.value.value);
					break;
			}
		}
		
		private function addToQueue(value:Object):void
		{
			queue.push(value);
		}
		
		private function listOfProcessEnded():void
		{
			switch (processType)
			{
				case GIT_CHECKOUT_BRANCH:
				case GIT_CHECKOUT_NEW_BRANCH:
				case GitHubPlugin.PULL_REQUEST:
					refreshProjectTree(); // important
					break;
			}
		}
		
		private function shellError(value:Object /** type of WorkerNativeProcessResult **/):void 
		{
			error(value.output);
		}
		
		private function shellExit(value:Object /** type of WorkerNativeProcessResult **/):void 
		{
			if (!isErrorClose) 
			{
				var tmpQueue:Object = value.queue; /** type of NativeProcessQueueVO **/
				switch (tmpQueue.processType)
				{
					case GitHubPlugin.CLONE_REQUEST:
						success("'"+ cloningProjectName +"'...downloaded successfully ("+ lastCloneURL + File.separator + cloningProjectName +")");
						break;
					case GIT_PUSH:
						success("...process completed");
						break;
					case GIT_DIFF_CHECK:
						checkDiffFileExistence();
						break;
				}
			}
		}
		
		private function shellTick(value:Object /** type of NativeProcessQueueVO **/):void
		{
			switch (value.processType)
			{
				case GIT_CHECKOUT_BRANCH:
					if (value.extraArguments) notice(value.extraArguments[0] +" :Finished");
					break;
			}
		}
		
		private function shellData(value:Object /** type of WorkerNativeProcessResult **/):void 
		{
			var match:Array;
			var tmpQueue:Object = value.queue; /** type of NativeProcessQueueVO **/
			var isFatal:Boolean;
			
			match = value.output.match(/fatal: .*/);
			if (match) isFatal = true;
			
			switch(tmpQueue.processType)
			{
				case XCODE_PATH_DECTECTION:
				{
					match = value.output.toLowerCase().match(/xcode.app\/contents\/developer/);
					if (match && (onXCodePathDetection != null))
					{
						onXCodePathDetection(value.output);
						return;
					}
					
					match = value.output.toLowerCase().match(/commandlinetools/);
					if (match && (onXCodePathDetection != null))
					{
						onXCodePathDetection(value.output);
						return;
					}
					break;
				}
				case GIT_AVAIL_DECTECTION:
				{
					match = value.output.toLowerCase().match(/git version/);
					if (match) 
					{
						setGitAvailable(true);
						return;
					}
					
					match = value.output.toLowerCase().match(/'git' is not recognized as an internal or external command/);
					if (match)
					{
						setGitAvailable(false);
						return;
					}
					break;
				}
				case GIT_REPOSITORY_TEST:
				{
					if (!isFatal)
					{
						gitTestProject.menuType += ","+ ProjectMenuTypes.GIT_PROJECT;
						if (plugin.modelAgainstProject[gitTestProject] == undefined) 
						{
							value.output = value.output.replace("\n", "");
							plugin.modelAgainstProject[gitTestProject] = new GitProjectVO();
							plugin.modelAgainstProject[gitTestProject].rootLocal = (value.output == ".git") ? gitTestProject.folderLocation.fileBridge.getFile as File : (new File(value.output)).parent;
						}
						
						// continuing fetch
						pendingProcess.push(new MethodDescriptor(this, 'getCurrentBranch')); // store the current branch
						pendingProcess.push(new MethodDescriptor(this, 'getGitRemoteURL')); // store the remote URL
						
						gitTestProject = null;
						dispatchEvent(new GeneralEvent(GIT_REPOSITORY_TEST));
					}
					else if (ConstantsCoreVO.IS_MACOS)
					{
						// in case of OSX sandbox if the project's parent folder
						// consists of '.git' and do not have bookmark access
						// the running command is tend to be fail, in that case
						// a brute check
						initiateSandboxGitRepositoryCheckBrute(gitTestProject);
					}
					return;
				}
				case GIT_REMOTE_ORIGIN_URL:
				{
					match = value.output.match(/.*.$/);
					if (match)
					{
						var tmpResult:Array = new RegExp("http.*\://", "i").exec(value.output);
						if (tmpResult != null)
						{
							// extracting remote origin URL as 'github/[author]/[project]
							if (plugin.modelAgainstProject[model.activeProject] != undefined) plugin.modelAgainstProject[model.activeProject].remoteURL = value.output.substr(tmpResult[0].length, value.output.length).replace("\n", "");
						}
						return;
					}
					break;
				}
				case GIT_CURRENT_BRANCH_NAME:
				{
					parseCurrentBranch(value.output);
					return;
				}
				case GitHubPlugin.CLONE_REQUEST:
				{
					match = value.output.toLowerCase().match(/cloning into/);
					if (match)
					{
						// for some weird reason git clone always
						// turns to errordata first
						cloningProjectName = value.output;
						warning(value.output);
						return;
					}
					break;
				}
				case GIT_REMOTE_BRANCH_LIST:
				{
					if (!isFatal) parseRemoteBranchList(value.output);
					return;
				}
			}
			
			if (isFatal)
			{
				error(value.output);
				isErrorClose = true;
				return;
			}
		}
		
		private function initiateSandboxGitRepositoryCheckBrute(value:AS3ProjectVO):void
		{
			var tmpFile:File = value.folderLocation.fileBridge.getFile as File;
			do
			{
				tmpFile = tmpFile.parent;
				if (tmpFile && tmpFile.resolvePath(".git").exists && tmpFile.resolvePath(".git/index").exists)
				{
					dispatchEvent(new GeneralEvent(GIT_REPOSITORY_TEST, {project:value, gitRootLocation:tmpFile}));
					break;
				}
				
			} while (tmpFile != null);
		}
		
		private function checkDiffFileExistence():void
		{
			var tmpFile:File = File.applicationStorageDirectory.resolvePath('commitDiff.txt');
			if (tmpFile.exists)
			{
				var value:String = new FileLocation(tmpFile.nativePath).fileBridge.read() as String;
				
				// @note
				// for some unknown reason, searchRegExp.exec(tmpString) always
				// failed after 4 records; initial investigation didn't shown
				// any possible reason of breaking; Thus forEach treatment for now
				// (but I don't like this)
				var tmpPositions:ArrayCollection = new ArrayCollection();
				var contentInLineBreaks:Array = value.split("\n");
				var firstPart:String;
				var secondPart:String;
				contentInLineBreaks.forEach(function(element:String, index:int, arr:Array):void
				{
					if (element != "")
					{
						element = StringUtil.trim(element);
						firstPart = element.substring(0, element.indexOf(" "));
						secondPart = element.substr(element.indexOf(" ")+1, element.length);
						
						// in some cases the output comes surrounding with double-quote
						// we need to remove them before a commit
						secondPart = secondPart.replace(/\"/g, "");
						secondPart = StringUtil.trim(secondPart);
						
						tmpPositions.addItem(new GenericSelectableObject(false, {path: secondPart, status:getFileStatus(firstPart)}));
					}
				});
				
				dispatchEvent(new GeneralEvent(GIT_DIFF_CHECKED, tmpPositions));
			}
			
			/*
			* @local
			*/
			function getFileStatus(value:String):String
			{
				if (value == "D") return GIT_STATUS_FILE_DELETED;
				else if (value == "??" || value == "A") return GIT_STATUS_FILE_NEW;
				return GIT_STATUS_FILE_MODIFIED;
			}
		}
		
		private function parseRemoteBranchList(value:String):void
		{
			if (model.activeProject && plugin.modelAgainstProject[model.activeProject] != undefined)
			{
				var tmpModel:GitProjectVO = plugin.modelAgainstProject[model.activeProject];
				
				tmpModel.branchList = new ArrayCollection();
				var contentInLineBreaks:Array = value.split("\n");
				contentInLineBreaks.forEach(function(element:String, index:int, arr:Array):void
				{
					if (element != "" && element.indexOf("origin/") != -1 && element.indexOf("->") == -1)
					{
						tmpModel.branchList.addItem(new GenericSelectableObject(false, element.substr(element.indexOf("origin/")+7, element.length)));
					}
				});
			}
		}
		
		private function parseCurrentBranch(value:String):void
		{
			var starredIndex:int = value.indexOf("* ") + 2;
			var selectedBranchName:String = value.substring(starredIndex, value.indexOf("\n", starredIndex));
			
			// store the project's selected branch to its model
			if (model.activeProject && plugin.modelAgainstProject[model.activeProject] != undefined)
			{
				var tmpModel:GitProjectVO = plugin.modelAgainstProject[model.activeProject];
				tmpModel.currentBranch = selectedBranchName;
				
				for each (var i:GenericSelectableObject in tmpModel.branchList)
				{
					if (i.data == selectedBranchName)
					{
						i.isSelected = true;
						dispatchEvent(new GeneralEvent(GIT_REMOTE_BRANCH_LIST, tmpModel.branchList));
						break;
					}
				}
			}
		}
		
		private function refreshProjectTree():void
		{
			// refreshing project tree
			GlobalEventDispatcher.getInstance().dispatchEvent(new ProjectEvent(ProjectEvent.PROJECT_FILES_UPDATES, model.activeProject.projectFolder));
		}
	}
}