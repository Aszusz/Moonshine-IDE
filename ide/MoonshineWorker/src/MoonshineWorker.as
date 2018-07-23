////////////////////////////////////////////////////////////////////////////////
//
//  Licensed to the Apache Software Foundation (ASF) under one or more
//  contributor license agreements.  See the NOTICE file distributed with
//  this work for additional information regarding copyright ownership.
//  The ASF licenses this file to You under the Apache License, Version 2.0
//  (the "License"); you may not use this file except in compliance with
//  the License.  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//
////////////////////////////////////////////////////////////////////////////////
package
{
	import flash.desktop.NativeProcess;
	import flash.desktop.NativeProcessStartupInfo;
	import flash.display.Sprite;
	import flash.events.Event;
	import flash.filesystem.File;
	import flash.filesystem.FileMode;
	import flash.filesystem.FileStream;
	import flash.geom.Point;
	import flash.system.MessageChannel;
	import flash.system.Worker;
	import flash.utils.clearTimeout;
	import flash.utils.setTimeout;
	
	import mx.utils.StringUtil;
	
	import actionScripts.events.WorkerEvent;
	import actionScripts.utils.WorkerGitNativeProcess;
	import actionScripts.valueObjects.WorkerFileWrapper;
	
	public class MoonshineWorker extends Sprite
	{
		public static const READABLE_FILES_PATTERNS:Array = ["as", "mxml", "css", "xml", "bat", "txt", "as3proj", "actionScriptProperties", "html", "js", "veditorproj"];
		
		public static var FILES_COUNT:int;
		public static var FILE_PROCESSED_COUNT:int;
		public static var FILES_FOUND_IN_COUNT:int;
		public static var IS_MACOS:Boolean;
		
		public var mainToWorker:MessageChannel;
		public var workerToMain:MessageChannel;
		
		private var projectSearchObject:Object;
		private var projects:Array;
		private var totalFoundCount:int;
		private var customFilePatterns:Array = [];
		private var isCustomFilePatterns:Boolean;
		private var isStorePathsForProbableReplace:Boolean;
		private var storedPathsForProbableReplace:Array;
		
		private var customProcess:NativeProcess;
		private var customInfo:NativeProcessStartupInfo;
		
		private var _gitProcess:WorkerGitNativeProcess;
		private function get gitProcess():WorkerGitNativeProcess
		{
			if (!_gitProcess)
			{
				_gitProcess = new WorkerGitNativeProcess();
				_gitProcess.worker = this;
			}
			
			return _gitProcess;
		}
		
		public function MoonshineWorker()
		{
			// receive from main
			mainToWorker = Worker.current.getSharedProperty("mainToWorker");
			// Send to main
			workerToMain = Worker.current.getSharedProperty("workerToMain");
			
			if (mainToWorker) mainToWorker.addEventListener(Event.CHANNEL_MESSAGE, onMainToWorker);
		}
		
		private function onMainToWorker(event:Event):void
		{
			var incomingObject:Object = mainToWorker.receive();
			switch (incomingObject.event)
			{
				case WorkerEvent.SET_IS_MACOS:
					IS_MACOS = incomingObject.value;
					break;
				case WorkerEvent.SEARCH_IN_PROJECTS:
					projectSearchObject = incomingObject;
					projects = projectSearchObject.value.projects;
					isStorePathsForProbableReplace = projectSearchObject.value.isShowReplaceWhenDone;
					FILES_FOUND_IN_COUNT = 0;
					storedPathsForProbableReplace = null;
					storedPathsForProbableReplace = [];
					parseProjectsTree();
					break;
				case WorkerEvent.REPLACE_FILE_WITH_VALUE:
					projectSearchObject = incomingObject;
					startReplacing();
					break;
				case WorkerEvent.GET_FILE_LIST:
					workerToMain.send({event:WorkerEvent.GET_FILE_LIST, value:storedPathsForProbableReplace});
					break;
				case WorkerEvent.SET_FILE_LIST:
					storedPathsForProbableReplace = incomingObject.value as Array;
					break;
				case WorkerEvent.RUN_LIST_OF_NATIVEPROCESS:
					gitProcess.runProcesses(incomingObject.value);
					break;
			}
		}
		
		private function parseProjectsTree():void
		{
			// probable termination
			if (projects.length == 0)
			{
				workerToMain.send({event:WorkerEvent.PROCESS_ENDS, value:FILES_FOUND_IN_COUNT});
				return;
			}
			
			FILES_COUNT = FILE_PROCESSED_COUNT = 0;
			totalFoundCount = 0;
			isCustomFilePatterns = false;
			
			var tmpWrapper:WorkerFileWrapper = new WorkerFileWrapper(new File(projects[0]), true);
			
			// in case a given path is not valid, do not parse anything
			if (!tmpWrapper.file.exists)
			{
				// restart with available next project (if any)
				projects.shift();
				var timeoutValue:uint = setTimeout(function():void
				{
					clearTimeout(timeoutValue);
					parseProjectsTree();
				}, 400);
				return;
			}
			
			workerToMain.send({event:WorkerEvent.TOTAL_FILE_COUNT, value:FILES_COUNT});
			
			if (projectSearchObject.value.patterns != "*")
			{
				var filtered:String = projectSearchObject.value.patterns.replace(/( )/g, "");
				customFilePatterns = filtered.split(",");
				
				var hasGloablSearchSign:Boolean = customFilePatterns.some(
					function isValidExtension(item:Object, index:int, arr:Array):Boolean {
						return item == "*";
					});
				
				isCustomFilePatterns = !hasGloablSearchSign;
			}
			
			parseChildrens(tmpWrapper);
		}
		
		private function parseChildrens(value:Object):void
		{
			if (!value) return;
			
			var extension: String = value.file.extension;
			var tmpReturnCount:int;
			var tmpLineObject:Object;
			
			if ((value.children is Array) && (value.children as Array).length > 0) 
			{
				var tmpTotalChildrenCount:int = value.children.length;
				for (var c:int=0; c < value.children.length; c++)
				{
					extension = value.children[c].file.extension;
					var isAcceptable:Boolean = (extension != null) ? isAcceptableResource(extension) : false;
					if (!value.children[c].file.isDirectory && isAcceptable)
					{
						tmpLineObject = testFilesForValueExist(value.children[c].file.nativePath);
						tmpReturnCount = tmpLineObject ? tmpLineObject.foundCountInFile : -1;
						if (tmpReturnCount == -1)
						{
							value.children.splice(c, 1);
							tmpTotalChildrenCount --;
							c--;
						}
						else
						{
							value.children[c].searchCount = tmpReturnCount;
							value.children[c].children = tmpLineObject.foundMatches;
							totalFoundCount += tmpReturnCount;
							FILES_FOUND_IN_COUNT++;
							if (isStorePathsForProbableReplace) storedPathsForProbableReplace.push({label:value.children[c].file.nativePath, isSelected:true});
						}
					}
					else if (!value.children[c].file.isDirectory && !isAcceptable)
					{
						value.children.splice(c, 1);
						tmpTotalChildrenCount --;
						c--;
					}
					else if (value.children[c].file.isDirectory) 
					{
						//lastChildren = value.children;
						parseChildrens(value.children[c]);
						if (!value.children[c].children || (value.children[c].children && value.children[c].children.length == 0)) 
						{
							value.children.splice(c, 1);
							c--;
						}
					}
					
					notifyFileCountCompletionToMain();
				}
				
				// when recursive listing done
				if (value.isRoot)
				{
					notifyFileCountCompletionToMain();
					workerToMain.send({event:WorkerEvent.TOTAL_FOUND_COUNT, value:value.file.nativePath +"::"+ totalFoundCount});
					workerToMain.send({event:WorkerEvent.FILTERED_FILE_COLLECTION, value:value});
					
					// restart with available next project (if any)
					projects.shift();
					var timeoutValue:uint = setTimeout(function():void
					{
						clearTimeout(timeoutValue);
						parseProjectsTree();
					}, 400);
				}
			}
			else 
			{
				notifyFileCountCompletionToMain();
			}
			
			/*
			 * @local
			 */
			function notifyFileCountCompletionToMain():void
			{
				tmpLineObject = null;
				workerToMain.send({event:WorkerEvent.FILE_PROCESSED_COUNT, value:++FILE_PROCESSED_COUNT});
			}
		}
		
		private function isAcceptableResource(extension:String):Boolean
		{
			if (isCustomFilePatterns)
			{
				return customFilePatterns.some(
					function isValidExtension(item:Object, index:int, arr:Array):Boolean {
						return item == extension;
					});
			}
			
			return READABLE_FILES_PATTERNS.some(
				function isValidExtension(item:Object, index:int, arr:Array):Boolean {
					return item == extension;
				});
		}
		
		private function startReplacing():void
		{
			for each (var i:Object in storedPathsForProbableReplace)
			{
				if (i.isSelected)
				{
					testFilesForValueExist(i.label, projectSearchObject.value.valueToReplace);
					workerToMain.send({event:WorkerEvent.FILE_PROCESSED_COUNT, value:i.label}); // sending path value instead of completion count in case of replace 
				}
			}
			
			// once done 
			workerToMain.send({event:WorkerEvent.PROCESS_ENDS, value:null});
		}
		
		private function testFilesForValueExist(value:String, replace:String=null):Object
		{
			var r:FileStream = new FileStream();
			var f:File = new File(value); 
			r.open(f, FileMode.READ);
			var content:String = r.readUTFBytes(f.size);
			r.close();
			
			// remove all the leading space/tabs in a line
			// so we can show the lines without having space/tabs in search results
			content = content.replace(/^[ \t]+(?=\S)/gm, "");
			content = StringUtil.trim(content);
			
			var searchString:String = projectSearchObject.value.isEscapeChars ? escapeRegex(projectSearchObject.value.valueToSearch) : projectSearchObject.value.valueToSearch;
			var flags:String = 'g';
			if (!projectSearchObject.value.isMatchCase) flags += 'i';
			var searchRegExp:RegExp = new RegExp(searchString, flags);
			
			//var foundMatches:Array = content.match(searchRegExp);
			
			var foundMatches:Array = [];
			var results:Array = searchRegExp.exec(content);
			var tmpFW:WorkerFileWrapper;
			var res:SearchResult;
			var lastLineIndex:int = -1;
			var foundCountInFile:int;
			var lines:Array;
			while (results != null)
			{
				var lc:Point = charIdx2LineCharIdx(content, results.index, "\n");
				
				res = new SearchResult();
				res.startLineIndex = lc.x;
				res.endLineIndex = lc.x;
				res.startCharIndex = lc.y;
				res.endCharIndex = lc.y + results[0].length;
				
				if (res.startLineIndex != lastLineIndex)
				{
					lines = content.split(/\r?\n|\r/);
					tmpFW = new WorkerFileWrapper(null);
					tmpFW.isShowAsLineNumber = true;
					tmpFW.lineNumbersWithRange = [];
					tmpFW.fileReference = value;
					foundMatches.push(tmpFW);
					lastLineIndex = res.startLineIndex;
				}
				
				//tmpFW.lineText = StringUtil.trim(lines[res.startLineIndex]);
				tmpFW.lineText = lines[res.startLineIndex];
				tmpFW.lineNumbersWithRange.push(res);
				results = searchRegExp.exec(content);
				
				// since a line could have multiple searched instance
				// we need to count do/while separately other than
				// counting total lines (foundMatches)
				foundCountInFile++;
			}
			
			if (foundMatches.length > 0 && replace)
			{
				replaceAndSaveFile();
			}
			
			lines = null;
			content = null;
			return ((foundMatches.length > 0) ? {foundMatches:foundMatches, foundCountInFile:foundCountInFile} : null);
			
			/*
			 * @local
			 */
			function replaceAndSaveFile():void
			{
				content = content.replace(searchRegExp, replace);
				
				r = new FileStream();
				r.open(f, FileMode.WRITE);
				r.writeUTFBytes(content);
				r.close();
			}
		}
		
		private function escapeRegex(str:String):String 
		{
			return str.replace(/[\$\(\)\*\+\.\[\]\?\\\^\{\}\|]/g,"\\$&");
		}
		
		private function charIdx2LineCharIdx(str:String, charIdx:int, lineDelim:String):Point
		{
			var line:int = str.substr(0,charIdx).split(lineDelim).length - 1;
			var chr:int = line > 0 ? charIdx - str.lastIndexOf(lineDelim, charIdx - 1) - lineDelim.length : charIdx;
			return new Point(line, chr);
		}
	}
}

class SearchResult
{
	public var startLineIndex:int = -1;
	public var startCharIndex:int = -1;
	public var endLineIndex:int = -1;
	public var endCharIndex:int = -1;
	public var totalMatches:int = 0;
	public var totalReplaces:int = 0;
	public var selectedIndex:int = 0;
	public var didWrap:Boolean;
	
	public function SearchResult() {}	
}