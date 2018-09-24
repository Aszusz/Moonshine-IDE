/*
Copyright 2016-2018 Bowler Hat LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/
package com.as3mxml.asconfigc;

import java.io.Console;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.apache.commons.cli.CommandLine;
import org.apache.commons.cli.CommandLineParser;
import org.apache.commons.cli.DefaultParser;
import org.apache.commons.cli.HelpFormatter;
import org.apache.commons.cli.Option;
import org.apache.commons.cli.Options;
import org.apache.commons.cli.ParseException;
import org.apache.commons.cli.UnrecognizedOptionException;

import com.fasterxml.jackson.core.JsonLocation;
import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.networknt.schema.JsonSchema;
import com.networknt.schema.JsonSchemaFactory;
import com.networknt.schema.ValidationMessage;
import com.as3mxml.asconfigc.air.AIROptions;
import com.as3mxml.asconfigc.air.AIROptionsParser;
import com.as3mxml.asconfigc.air.AIRSigningOptions;
import com.as3mxml.asconfigc.compiler.CompilerOptions;
import com.as3mxml.asconfigc.compiler.CompilerOptionsParser;
import com.as3mxml.asconfigc.compiler.ConfigName;
import com.as3mxml.asconfigc.compiler.JSOutputType;
import com.as3mxml.asconfigc.compiler.ProjectType;
import com.as3mxml.asconfigc.compiler.RoyaleTarget;
import com.as3mxml.asconfigc.utils.ApacheFlexJSUtils;
import com.as3mxml.asconfigc.utils.ApacheRoyaleUtils;
import com.as3mxml.asconfigc.utils.GenericSDKUtils;
import com.as3mxml.asconfigc.utils.JsonUtils;
import com.as3mxml.asconfigc.utils.OptionsFormatter;
import com.as3mxml.asconfigc.utils.ProjectUtils;

/**
 * Parses asconfig.json and executes the compiler with the specified options.
 * Can also, optionally, run adt (the AIR Developer Tool) to package an Adobe
 * AIR application.
 */
public class ASConfigC
{
	private static final String FILE_EXTENSION_AS = ".as";
	private static final String FILE_EXTENSION_MXML = ".mxml";

	public static void main(String[] args)
	{
		CommandLineParser parser = new DefaultParser();

		Options options = new Options();
		options.addOption(new Option("h", "help", false, "Print this help message."));
		options.addOption(new Option("v", "version", false, "Print the version."));
		Option projectOption = new Option("p", "project", true, "Compile a project with the path to its configuration file or a directory containing asconfig.json. If omitted, will look for asconfig.json in current directory.");
		projectOption.setArgName("FILE OR DIRECTORY");
		options.addOption(projectOption);
		Option sdkOption = new Option(null, "sdk", true, "Specify the directory where the ActionScript SDK is located. If omitted, defaults to checking ROYALE_HOME, FLEX_HOME and PATH environment variables.");
		sdkOption.setArgName("DIRECTORY");
		options.addOption(sdkOption);
		Option debugOption = new Option(null, "debug", true, "Specify debug or release mode. Overrides the debug compiler option, if specified in asconfig.json.");
		debugOption.setArgName("true OR false");
		debugOption.setOptionalArg(true);
		options.addOption(debugOption);
		Option airOption = new Option(null, "air", true, "Package the project as an Adobe AIR application. The allowed platforms include `android`, `ios`, `windows`, `mac`, and `air`.");
		airOption.setArgName("PLATFORM");
		airOption.setOptionalArg(true);
		options.addOption(airOption);

		ASConfigCOptions asconfigcOptions = null;
		try
		{
			CommandLine line = parser.parse(options, args);
			if(line.hasOption("h"))
			{
				String syntax = "asconfigc [options]\n\n" +
								"Examples: asconfigc\n" +
								"          asconfigc -p .\n" +
								"          asconfigc -p path/to/custom.json\n\n" +
								"Options:";
				HelpFormatter formatter = new HelpFormatter();
				formatter.setSyntaxPrefix("Syntax:   ");
				formatter.printHelp(syntax, options);
				System.exit(0);
			}
			if(line.hasOption("v"))
			{
				String version = ASConfigC.class.getPackage().getImplementationVersion();
				System.out.println("Version: " + version);
				System.exit(0);
			}
			asconfigcOptions = new ASConfigCOptions(line);
		}
		catch(UnrecognizedOptionException e)
		{
			System.err.println("Unknown asconfigc option: " + e.getOption());
			System.exit(1);
		}
		catch(ParseException e)
		{
			System.err.println("Failed to parse asconfigc options.");
			e.printStackTrace(System.err);
			System.exit(1);
		}

		try
		{
			new ASConfigC(asconfigcOptions);
		}
		catch(ASConfigCException e)
		{
			if(e.status != 0)
			{
				System.exit(e.status);
			}
			System.err.println(e.getMessage());
			System.exit(1);
		}
	}

	private static final String ASCONFIG_JSON = "asconfig.json";
	private static final Pattern ADDITIONAL_OPTIONS_PATTERN = Pattern.compile("\"([^\"]*)\"|(\\S+)");

	public ASConfigC(ASConfigCOptions options) throws ASConfigCException
	{
		this.options = options;
		File configFile = findConfigurationFile(options.project);

		//the current working directory must be where asconfig.json is located
		System.setProperty("user.dir", configFile.getParent());

		JsonNode json = loadConfig(configFile);
		parseConfig(json);
		validateSDK();
		compileProject();
		copySourcePathAssets();
		processAdobeAIRDescriptor();
		copyAIRFiles();
		packageAIR();
	}

	private ASConfigCOptions options;
	private List<String> compilerOptions;
	private List<String> airOptions;
	private JsonNode airOptionsJSON;
	private String projectType;
	private boolean debugBuild;
	private boolean copySourcePathAssets;
	private String jsOutputType;
	private String outputPath;
	private String mainFile;
	private String airDescriptorPath;
	private List<String> sourcePaths;
	private boolean configRequiresRoyale;
	private boolean configRequiresRoyaleOrFlexJS;
	private boolean configRequiresFlexJS;
	private boolean sdkIsRoyale;
	private boolean sdkIsFlexJS;
	private boolean isSWFTargetOnly;
	private boolean outputIsJS;
	private String sdkHome;

	private File findConfigurationFile(String projectPath) throws ASConfigCException
	{
		File projectFile = null;
		if(projectPath != null)
		{
			projectFile = new File(projectPath);
		}
		else
		{
			projectFile = new File(System.getProperty("user.dir"));
		}
		if(!projectFile.exists())
		{
			throw new ASConfigCException("Project directory or JSON file not found: " + projectFile.getAbsolutePath());
		}
		if(projectFile.isDirectory())
		{
			File configFile = new File(projectFile, ASCONFIG_JSON);
			if(!configFile.exists())
			{
				throw new ASConfigCException("asconfig.json not found in directory: " + projectFile.getAbsolutePath());
			}
			return configFile;
		}
		return projectFile;
	}

	private JsonNode loadConfig(File configFile) throws ASConfigCException
	{
        JsonSchema schema = null;
        try (InputStream schemaInputStream = getClass().getResourceAsStream("/schemas/asconfig.schema.json"))
        {
            JsonSchemaFactory factory = JsonSchemaFactory.getInstance();
            schema = factory.getSchema(schemaInputStream);
        }
        catch(Exception e)
        {
            //this exception is unexpected, so it should be reported
            throw new ASConfigCException("Failed to load asconfig.json schema: " + e);
        }
        JsonNode json = null;
        try
        {
            String contents = new String(Files.readAllBytes(configFile.toPath()));
            ObjectMapper mapper = new ObjectMapper();
            //VSCode allows comments, so we should too
            mapper.configure(JsonParser.Feature.ALLOW_COMMENTS, true);
            mapper.configure(JsonParser.Feature.ALLOW_TRAILING_COMMA, true);
            json = mapper.readTree(contents);
            Set<ValidationMessage> errors = schema.validate(json);
            if (!errors.isEmpty())
            {
				StringBuilder combinedMessage = new StringBuilder();
				combinedMessage.append("Invalid asconfig.json:\n");
				for(ValidationMessage error : errors)
				{
					combinedMessage.append(error.getMessage() + "\n");
				}
            	throw new ASConfigCException(combinedMessage.toString());
            }
		}
		catch(JsonProcessingException e)
		{
			//this exception is expected sometimes if the JSON is invalid
			JsonLocation location = e.getLocation();
			throw new ASConfigCException("Invalid asconfig.json:\n" + e.getOriginalMessage() + " (line " + location.getLineNr() + ", column " + location.getColumnNr() + ")");
		}
        catch(IOException e)
        {
			throw new ASConfigCException("Failed to read asconfig.json: " + e);
		}
		return json;
	}
	
	private void parseConfig(JsonNode json) throws ASConfigCException
	{
		debugBuild = options.debug != null && options.debug.equals(true);
		compilerOptions = new ArrayList<>();
		if(options.debug != null)
		{
			OptionsFormatter.setBoolean(CompilerOptions.DEBUG, options.debug, compilerOptions);
		}
		airOptions = new ArrayList<>();
		jsOutputType = null;
		projectType = ProjectType.APP;
		if(json.has(TopLevelFields.TYPE))
		{
			projectType = json.get(TopLevelFields.TYPE).asText();
		}
		if(json.has(TopLevelFields.CONFIG))
		{
			String configName = json.get(TopLevelFields.CONFIG).asText();
			detectJavaScript(configName);
			compilerOptions.add("+configname=" + configName);
		}
		if(json.has(TopLevelFields.COMPILER_OPTIONS))
		{
			JsonNode compilerOptions = json.get(TopLevelFields.COMPILER_OPTIONS);
			readCompilerOptions(compilerOptions);
			if(options.debug == null && compilerOptions.has(CompilerOptions.DEBUG) &&
				compilerOptions.get(CompilerOptions.DEBUG).asBoolean() == true)
			{
				debugBuild = true;
			}
			if(compilerOptions.has(CompilerOptions.SOURCE_PATH))
			{
				JsonNode sourcePath = compilerOptions.get(CompilerOptions.SOURCE_PATH);
				sourcePaths = JsonUtils.jsonNodeToListOfStrings(sourcePath);
			}
			if(compilerOptions.has(CompilerOptions.OUTPUT))
			{
				outputPath = compilerOptions.get(CompilerOptions.OUTPUT).asText();
			}
		}
		if(json.has(TopLevelFields.ADDITIONAL_OPTIONS))
		{
			String additionalOptions = json.get(TopLevelFields.ADDITIONAL_OPTIONS).asText();
			if(additionalOptions != null)
			{
				//parse the additional options by splitting on whitespace
				//except when an option is wrapped in quotes
				Matcher matcher = ADDITIONAL_OPTIONS_PATTERN.matcher(additionalOptions);
				while(matcher.find())
				{
					String quotedOption = matcher.group(1);
					if(quotedOption != null)
					{
						compilerOptions.add(quotedOption);
					}
					else //not quoted
					{
						compilerOptions.add(matcher.group(2));
					}
				}
			}
		}
		if(json.has(TopLevelFields.APPLICATION))
		{
			airDescriptorPath = json.get(TopLevelFields.APPLICATION).asText();
			File airDescriptor = new File(airDescriptorPath);
			if(!airDescriptor.isAbsolute())
			{
				airDescriptor = new File(System.getProperty("user.dir"), airDescriptorPath);
			}
			if(!airDescriptor.exists() || airDescriptor.isDirectory())
			{
				throw new ASConfigCException("Adobe AIR application descriptor not found: " + airDescriptor);
			}
		}
		//parse files before airOptions because the mainFile may be
		//needed to generate some file paths
		if(json.has(TopLevelFields.FILES))
		{
			JsonNode files = json.get(TopLevelFields.FILES);
			if(projectType.equals(ProjectType.LIB))
			{
				for(int i = 0, size = files.size(); i < size; i++)
				{
					String file = files.get(i).asText();
					compilerOptions.add("--include-sources+=" + file);
				}
			}
			else
			{
				int size = files.size();
				for(int i = 0; i < size; i++)
				{
					String file = files.get(i).asText();
					compilerOptions.add(file);
				}
				if(size > 0)
				{
					mainFile = files.get(size - 1).asText();
				}
			}
		}
		if(json.has(TopLevelFields.AIR_OPTIONS))
		{
			if(airDescriptorPath == null)
			{
				throw new ASConfigCException("Adobe AIR packaging options found, but the \"application\" field is empty.");
			}
			airOptionsJSON = json.get(TopLevelFields.AIR_OPTIONS);
			readAIROptions(airOptionsJSON);
		}
		if(json.has(TopLevelFields.COPY_SOURCE_PATH_ASSETS))
		{
			copySourcePathAssets = json.get(TopLevelFields.COPY_SOURCE_PATH_ASSETS).asBoolean();
		}
		//if js-output-type was not specified, use the default
		//swf projects won't have a js-output-type
		if(jsOutputType != null)
		{
			compilerOptions.add("--" + CompilerOptions.JS_OUTPUT_TYPE + "=" + jsOutputType);
		}
	}

	private void detectJavaScript(String configName)
	{
		switch(configName)
		{
			case ConfigName.JS:
			{
				jsOutputType = JSOutputType.JSC;
				configRequiresRoyaleOrFlexJS = true;
				break;
			}
			case ConfigName.NODE:
			{
				jsOutputType = JSOutputType.NODE;
				configRequiresRoyaleOrFlexJS = true;
				break;
			}
			case ConfigName.ROYALE:
			{
				//this option is not supported by FlexJS
				configRequiresRoyale = true;
				break;
			}
		}
	}
	
	private void readCompilerOptions(JsonNode compilerOptionsJson) throws ASConfigCException
	{
		CompilerOptionsParser parser = new CompilerOptionsParser();
		try
		{
			parser.parse(compilerOptionsJson, options.debug, compilerOptions);
		}
		catch(Exception e)
		{
			StringWriter stackTrace = new StringWriter();
			e.printStackTrace(new PrintWriter(stackTrace));
			throw new ASConfigCException("Error: Failed to parse compiler options.\n" + stackTrace.toString());
		}
		//make sure that we require Royale (or FlexJS) depending on which options are specified
		if(compilerOptionsJson.has(CompilerOptions.JS_OUTPUT_TYPE))
		{
			//this option was used in FlexJS 0.7, but it was replaced with
			//targets in FlexJS 0.8.
			configRequiresFlexJS = true;
			//if it is set explicitly, then clear the default
			jsOutputType = null;
		}
		if(compilerOptionsJson.has(CompilerOptions.TARGETS))
		{
			JsonNode targets = compilerOptionsJson.get(CompilerOptions.TARGETS);
			boolean foundRoyaleTarget = false;
			for(JsonNode target : targets)
			{
				String targetAsText = target.asText();
				if(targetAsText.equals(RoyaleTarget.JS_ROYALE) ||
					targetAsText.equals(RoyaleTarget.JS_ROYALE_CORDOVA))
				{
					//these targets definitely don't work with FlexJS
					configRequiresRoyale = true;
					foundRoyaleTarget = true;
				}
				if(targetAsText.equals(RoyaleTarget.SWF))
				{
					isSWFTargetOnly = targets.size() == 1;
				}
			}
			if(!foundRoyaleTarget)
			{
				//remaining targets are supported by both Royale and FlexJS
				configRequiresRoyaleOrFlexJS = true;
			}
			//if targets is set explicitly, then we're using a newer SDK
			//that doesn't need js-output-type
			jsOutputType = null;
		}
		if(compilerOptionsJson.has(CompilerOptions.SOURCE_MAP))
		{
			//source-map compiler option is supported by both Royale and FlexJS
			configRequiresRoyaleOrFlexJS = true;
		}
	}
	
	private void readAIROptions(JsonNode airOptionsJson) throws ASConfigCException
	{
		if(options.air == null)
		{
			return;
		}
		AIROptionsParser parser = new AIROptionsParser();
		try
		{
			parser.parse(
				options.air,
				debugBuild,
				ProjectUtils.findAIRDescriptorOutputPath(mainFile, airDescriptorPath, outputPath, !outputIsJS, debugBuild),
				ProjectUtils.findApplicationContentOutputPath(mainFile, outputPath, !outputIsJS, debugBuild),
				airOptionsJson,
				airOptions);
		}
		catch(Exception e)
		{
			StringWriter stackTrace = new StringWriter();
			e.printStackTrace(new PrintWriter(stackTrace));
			throw new ASConfigCException("Error: Failed to parse Adobe AIR options.\n" + stackTrace.toString());
		}
	}

	private void validateSDK() throws ASConfigCException
	{
		sdkHome = options.sdk;
		if(sdkHome == null)
		{
			sdkHome = ApacheRoyaleUtils.findSDK();
		}
		if(sdkHome == null && !configRequiresRoyale)
		{
			sdkHome = ApacheFlexJSUtils.findSDK();
		}
		if(sdkHome == null &&
			!configRequiresRoyale &&
			!configRequiresRoyaleOrFlexJS &&
			!configRequiresFlexJS)
		{
			sdkHome = GenericSDKUtils.findSDK();
		}
		if(sdkHome == null)
		{
			String envHome = "FLEX_HOME";
			if(configRequiresRoyale)
			{
				envHome = "ROYALE_HOME";
			}
			else if(configRequiresRoyaleOrFlexJS)
			{
				envHome = "ROYALE_HOME for Apache Royale, FLEX_HOME for Apache FlexJS";
			}
			throw new ASConfigCException("SDK not found. Set " + envHome + ", add SDK to PATH environment variable, or use --sdk option.");
		}
		Path sdkHomePath = Paths.get(sdkHome);
		Path royalePath = ApacheRoyaleUtils.isValidSDK(sdkHomePath);
		if(royalePath != null)
		{
			sdkHomePath = royalePath;
			sdkIsRoyale = true;
		}
		if(configRequiresRoyale && !sdkIsRoyale)
		{
			throw new ASConfigCException("Configuration options in asconfig.json require Apache Royale. Path to SDK is not valid: " + sdkHome);
		}
		sdkIsFlexJS = ApacheFlexJSUtils.isValidSDK(sdkHomePath);
		if(configRequiresRoyaleOrFlexJS && !sdkIsRoyale && !sdkIsFlexJS)
		{
			throw new ASConfigCException("Configuration options in asconfig.json require Apache Royale or FlexJS. Path to SDK is not valid: " + sdkHome);
		}
		if(configRequiresFlexJS && !sdkIsFlexJS)
		{
			throw new ASConfigCException("Configuration options in asconfig.json require Apache FlexJS. Path to SDK is not valid: " + sdkHome);
		}
		outputIsJS = (sdkIsRoyale || sdkIsFlexJS) && !isSWFTargetOnly;
	}
	
	private void compileProject() throws ASConfigCException
	{
		options.compiler.compile(projectType, compilerOptions, Paths.get(System.getProperty("user.dir")), Paths.get(sdkHome));
	}

	private void copySourcePathAssetToOutputDirectory(String assetPath, String mainFile, List<String> sourcePaths, String outputDirectory) throws ASConfigCException
	{
		String targetPath = null;
		try
		{
			targetPath = ProjectUtils.assetPathToOutputPath(assetPath, mainFile, sourcePaths, outputDirectory);
		}
		catch(IOException e)
		{
			throw new ASConfigCException(e.getMessage());
		}
		File targetFile = new File(targetPath);
		File targetParent = targetFile.getParentFile();
		if(!targetParent.exists() && !targetParent.mkdirs())
		{
			throw new ASConfigCException("Failed to copy file from source " + assetPath + " to destination " + targetParent.getAbsolutePath() + " because the directories could not be created.");
		}
		try
		{
			Files.copy(Paths.get(assetPath), targetFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
		}
		catch(IOException e)
		{
			throw new ASConfigCException("Failed to copy file from source " + assetPath + " to destination " + targetPath);
		}
	}
	
	private void copySourcePathAssets() throws ASConfigCException
	{
		if(!copySourcePathAssets)
		{
			return;
		}
		List<String> pathsToSearch = new ArrayList<>();
		if(sourcePaths != null)
		{
			pathsToSearch.addAll(sourcePaths);
		}
		String outputDirectory = ProjectUtils.findOutputDirectory(mainFile, outputPath, !outputIsJS);
		ArrayList<String> excludes = new ArrayList<>();
		if(airDescriptorPath != null)
		{
			excludes.add(airDescriptorPath);
		}
		List<String> assetPaths = null;
		try
		{
			assetPaths = ProjectUtils.findSourcePathAssets(mainFile, sourcePaths, outputDirectory, excludes, Arrays.asList(FILE_EXTENSION_AS, FILE_EXTENSION_MXML));
		}
		catch(IOException e)
		{
			throw new ASConfigCException(e.getMessage());
		}
		for(String assetPath : assetPaths)
		{
			if(outputIsJS)
			{
				File outputDirectoryJSDebug = new File(outputDirectory, "bin/js-debug");
				copySourcePathAssetToOutputDirectory(assetPath, mainFile, sourcePaths, outputDirectoryJSDebug.getAbsolutePath());
				if(!debugBuild)
				{
					File outputDirectoryJSRelease = new File(outputDirectory, "bin/js-release");
					copySourcePathAssetToOutputDirectory(assetPath, mainFile, sourcePaths, outputDirectoryJSRelease.getAbsolutePath());
				}
			}
			else //swf
			{
				copySourcePathAssetToOutputDirectory(assetPath, mainFile, sourcePaths, outputDirectory);
			}
		}
	}
	
	private void copyAIRFiles() throws ASConfigCException
	{
		if(options.air != null)
		{
			//don't copy anything when packaging an app. these files are used
			//for debug builds only.
			return;
		}
		if(airOptionsJSON == null)
		{
			//the airOptions field is not defined, so there's nothing to copy
			return;
		}
		if(!airOptionsJSON.has(AIROptions.FILES))
		{
			//the files field is not defined, so there's nothing to copy
			return;
		}

		String outputDirectoryPath = ProjectUtils.findOutputDirectory(mainFile, outputPath, !outputIsJS);
		File outputDirectory = new File(outputDirectoryPath);

		JsonNode filesJSON = airOptionsJSON.get(AIROptions.FILES);
		for(int i = 0, size = filesJSON.size(); i < size; i++)
		{
			JsonNode fileJSON = filesJSON.get(i);
			if(fileJSON.isTextual())
			{
				String filePath = fileJSON.asText();
				File srcFile = new File(filePath);
				try
				{
					if(outputIsJS)
					{
						File outputDirectoryJSDebug = new File(outputDirectory, "bin/js-debug");
						File destFileKSDebug = new File(outputDirectoryJSDebug, srcFile.getName());
						Files.copy(srcFile.toPath(), destFileKSDebug.toPath(), StandardCopyOption.REPLACE_EXISTING);
						if(!debugBuild)
						{
							File outputDirectoryJSRelease = new File(outputDirectory, "bin/js-release");
							File destFileJSRelease = new File(outputDirectoryJSRelease, srcFile.getName());
							Files.copy(srcFile.toPath(), destFileJSRelease.toPath(), StandardCopyOption.REPLACE_EXISTING);
						}
					}
					else //swf
					{
						File destFile = new File(outputDirectory, srcFile.getName());
						Files.copy(srcFile.toPath(), destFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
					}
				}
				catch(IOException e)
				{
					throw new ASConfigCException(e.getMessage());
				}
			}
			else
			{
				String srcFilePath = fileJSON.get(AIROptions.FILES__FILE).asText();
				File srcFile = new File(srcFilePath);
				if(!srcFile.isAbsolute())
				{
					srcFile = new File(System.getProperty("user.dir"), srcFilePath);
				}

				String destFilePath = fileJSON.get(AIROptions.FILES__PATH).asText();
				File destFile = new File(outputDirectory, destFilePath);

				Path relativePath = outputDirectory.toPath().relativize(destFile.toPath());
				try
				{
					if(relativePath.toString().startsWith("..") || destFile.getCanonicalPath().equals(outputDirectory.getCanonicalPath()))
					{
						throw new ASConfigCException("Invalid destination path for file in Adobe AIR application. Source: " + srcFilePath + ", Destination: " + destFilePath);
					}
				}
				catch(IOException e)
				{
					throw new ASConfigCException(e.getMessage());
				}

				if(srcFile.isDirectory())
				{
					List<String> assetDirList = Arrays.asList(srcFile.getAbsolutePath());
					List<String> assetPaths = null;
					try
					{
						assetPaths = ProjectUtils.findSourcePathAssets(null, assetDirList, outputDirectory.getAbsolutePath(), null, null);
					}
					catch(IOException e)
					{
						throw new ASConfigCException(e.getMessage());
					}
					assetDirList = Arrays.asList(srcFile.getParentFile().getAbsolutePath());
					for(String assetPath : assetPaths)
					{
						if(outputIsJS)
						{
							File outputDirectoryJSDebug = new File(outputDirectory, "bin/js-debug");
							copySourcePathAssetToOutputDirectory(assetPath, null, assetDirList, outputDirectoryJSDebug.getAbsolutePath());
							if(!debugBuild)
							{
								File outputDirectoryJSRelease = new File(outputDirectory, "bin/js-release");
								copySourcePathAssetToOutputDirectory(assetPath, null, assetDirList, outputDirectoryJSRelease.getAbsolutePath());
							}
						}
						else //swf
						{
							copySourcePathAssetToOutputDirectory(assetPath, null, assetDirList, outputDirectory.getAbsolutePath());
						}
					}
				}
				else
				{
					try
					{
						if(outputIsJS)
						{
							File outputDirectoryJSDebug = new File(outputDirectory, "bin/js-debug");
							File destFileKSDebug = new File(outputDirectoryJSDebug, destFilePath);
							Files.copy(srcFile.toPath(), destFileKSDebug.toPath(), StandardCopyOption.REPLACE_EXISTING);
							if(!debugBuild)
							{
								File outputDirectoryJSRelease = new File(outputDirectory, "bin/js-release");
								File destFileJSRelease = new File(outputDirectoryJSRelease, destFilePath);
								Files.copy(srcFile.toPath(), destFileJSRelease.toPath(), StandardCopyOption.REPLACE_EXISTING);
							}
						}
						else //swf
						{
							Files.copy(srcFile.toPath(), destFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
						}
					}
					catch(IOException e)
					{
						throw new ASConfigCException(e.getMessage());
					}
				}
			}
		}
	}

	private void copyAIRDescriptor(String descriptorOutputPath, String descriptorContents) throws ASConfigCException
	{
		File descriptorOutputFile = new File(descriptorOutputPath);
		File descriptorOutputParent = descriptorOutputFile.getParentFile();
		if(!descriptorOutputParent.exists() && !descriptorOutputParent.mkdirs())
		{
			throw new ASConfigCException("Failed to copy Adobe AIR application descriptor to path: " + descriptorOutputPath + " because the directories could not be created.");
		}
		try
		{
			Files.write(descriptorOutputFile.toPath(), descriptorContents.getBytes());
		}
		catch(IOException e)
		{
			throw new ASConfigCException("Failed to copy Adobe AIR application descriptor to path: " + descriptorOutputPath);
		}
	}
	
	private void processAdobeAIRDescriptor() throws ASConfigCException
	{
		if(airDescriptorPath == null)
		{
			return;
		}
		String outputDirectory = ProjectUtils.findOutputDirectory(mainFile, outputPath, !outputIsJS);
		String contentValue = ProjectUtils.findApplicationContent(mainFile, outputPath, !outputIsJS);
		if(contentValue == null)
		{
			throw new ASConfigCException("Failed to find content for Adobe AIR application descriptor.");
		}
		Path finalDescriptorPath = Paths.get(airDescriptorPath);
		if(!finalDescriptorPath.isAbsolute())
		{
			finalDescriptorPath = Paths.get(System.getProperty("user.dir"), airDescriptorPath);
		}
		String descriptorContents = null;
		try
		{
			descriptorContents = new String(Files.readAllBytes(finalDescriptorPath));
		}
		catch(IOException e)
		{
			throw new ASConfigCException("Failed to read Adobe AIR application descriptor at path: " + airDescriptorPath);
		}
		descriptorContents = ProjectUtils.populateAdobeAIRDescriptorContent(descriptorContents, contentValue);
		if(outputIsJS)
		{
			String debugDescriptorOutputPath = ProjectUtils.findAIRDescriptorOutputPath(mainFile, airDescriptorPath, outputDirectory, false, true);
			copyAIRDescriptor(debugDescriptorOutputPath, descriptorContents);
			if(!debugBuild)
			{
				String releaseDescriptorOutputPath = ProjectUtils.findAIRDescriptorOutputPath(mainFile, airDescriptorPath, outputDirectory, false, false);
				copyAIRDescriptor(releaseDescriptorOutputPath, descriptorContents);
			}
			
		}
		else //swf
		{
			String descriptorOutputPath = ProjectUtils.findAIRDescriptorOutputPath(mainFile, airDescriptorPath, outputPath, true, debugBuild);
			copyAIRDescriptor(descriptorOutputPath, descriptorContents);
		}
	}
	
	private void packageAIR() throws ASConfigCException
	{
		if(options.air == null)
		{
			return;
		}
		Path jarPath = ProjectUtils.findAdobeAIRPackagerJarPath(sdkHome);
		if(jarPath == null)
		{
			throw new ASConfigCException("AIR ADT not found in SDK. Expected: " + Paths.get(sdkHome, "lib", "adt.jar"));
		}

		//if the certificate password isn't already specified, ask for it and add it
		int passwordIndex = airOptions.indexOf("-" + AIRSigningOptions.STOREPASS);
		if(passwordIndex == -1)
		{
			int keystoreIndex = airOptions.indexOf("-" + AIRSigningOptions.KEYSTORE);
			if(keystoreIndex != -1)
			{
				//only ask for password if -keystore is specified
				Console console = System.console();
				char[] password = console.readPassword("Adobe AIR code signing password: ");
				airOptions.add(keystoreIndex + 2, "-" + AIRSigningOptions.STOREPASS);
				airOptions.add(keystoreIndex + 3, new String(password));
			}
		}

		Path javaExecutablePath = Paths.get(System.getProperty("java.home"), "bin", "java");
		airOptions.add(0, jarPath.toString());
		airOptions.add(0, "-jar");
		airOptions.add(0, javaExecutablePath.toString());
		try
		{
			File cwd = new File(System.getProperty("user.dir"));
			Process process = new ProcessBuilder()
				.command(airOptions)
				.directory(cwd)
				.inheritIO()
				.start();
			int status = process.waitFor();
			if(status != 0)
			{
				throw new ASConfigCException(status);
			}
		}
		catch(InterruptedException e)
		{
			throw new ASConfigCException("Failed to execute Adobe AIR packager: " + e.getMessage());
		}
		catch(IOException e)
		{
			throw new ASConfigCException("Failed to execute Adobe AIR Packager: " + e.getMessage());
		}
	}
}