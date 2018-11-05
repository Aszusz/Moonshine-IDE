package actionScripts.plugin.actionscript.as3project.vo
{
    import actionScripts.plugin.build.vo.BuildActionVO;
    import actionScripts.utils.UtilsCore;

    import mx.utils.StringUtil;

    public class MavenBuildOptions
    {
        public static var defaultOptions:MavenBuildOptions = new MavenBuildOptions(null);

        private var _defaultMavenBuildPath:String;
        private var _buildActions:Array;

        public function MavenBuildOptions(defaultMavenBuildPath:String)
        {
            _defaultMavenBuildPath = defaultMavenBuildPath;
            _buildActions = [
                new BuildActionVO("Build", "install"),
                new BuildActionVO("Clean", "clean"),
                new BuildActionVO("Clean and Build", "clean install")
            ]
        }

        public var commandLine:String;
        public var settingsFilePath:String;

        private var _mavenBuildPath:String;
        public function get mavenBuildPath():String
        {
            return !_mavenBuildPath ? _defaultMavenBuildPath : _mavenBuildPath;
        }

        public function set mavenBuildPath(value:String):void
        {
            _mavenBuildPath = value;
        }

        public function get buildActions():Array
        {
            return _buildActions;
        }

        public function getCommandLine():Array
        {
            var commandLineOptions:Array = [];
            if (commandLine)
            {
                commandLineOptions = commandLine.split(" ");
                commandLineOptions = commandLineOptions.filter(function(item:String, index:int, arr:Array):Boolean{
                    item = StringUtil.trim(item);
                    if (item)
                    {
                        return true;
                    }

                    return false;
                });
            }

            if (settingsFilePath)
            {
                commandLineOptions.push("-s" + settingsFilePath);
            }

            return commandLineOptions;
        }

        public function parse(build:XMLList):void
        {
            var options:XMLList = build.option;

            mavenBuildPath = UtilsCore.deserializeString(options.@mavenBuildPath);
            commandLine = UtilsCore.deserializeString(options.@commandLine);
            settingsFilePath = UtilsCore.deserializeString(options.@settingsFilePath);
        }

        public function toXML():XML
        {
            var build:XML = <mavenBuild/>;

            var pairs:Object = {
                mavenBuildPath: UtilsCore.serializeString(mavenBuildPath),
                commandLine: UtilsCore.serializeString(commandLine),
                settingsFilePath: UtilsCore.serializeString(settingsFilePath)
            }

            build.appendChild(UtilsCore.serializePairs(pairs, <option/>));

            return build;
        }
    }
}
