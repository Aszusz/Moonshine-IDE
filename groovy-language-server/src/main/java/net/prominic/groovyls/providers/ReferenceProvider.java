////////////////////////////////////////////////////////////////////////////////
// Copyright 2019 Prominic.NET, Inc.
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
package net.prominic.groovyls.providers;

import java.net.URI;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.stream.Collectors;

import com.palantir.ls.groovy.util.GroovyLocations;

import org.codehaus.groovy.ast.ASTNode;
import org.eclipse.lsp4j.Location;
import org.eclipse.lsp4j.Position;
import org.eclipse.lsp4j.TextDocumentIdentifier;

import net.prominic.groovyls.compiler.ast.ASTNodeVisitor;
import net.prominic.groovyls.compiler.util.GroovyASTUtils;

public class ReferenceProvider {
	private ASTNodeVisitor ast;

	public ReferenceProvider(ASTNodeVisitor ast) {
		this.ast = ast;
	}

	public CompletableFuture<List<? extends Location>> provideReferences(TextDocumentIdentifier textDocument,
			Position position) {
		URI documentURI = URI.create(textDocument.getUri());
		ASTNode offsetNode = ast.getNodeAtLineAndColumn(documentURI, position.getLine(), position.getCharacter());

		ASTNode definitionNode = GroovyASTUtils.getDefinition(offsetNode, ast);
		if (definitionNode == null) {
			return CompletableFuture.completedFuture(Collections.emptyList());
		}

		List<ASTNode> nodes = ast.getNodes();

		List<Location> locations = nodes.stream().filter(node -> {
			ASTNode otherDefinition = GroovyASTUtils.getDefinition(node, ast);
			return definitionNode.equals(otherDefinition);
		}).map(node -> {
			URI uri = ast.getURI(node);
			return GroovyLocations.createLocation(uri, node);
		}).collect(Collectors.toList());

		return CompletableFuture.completedFuture(locations);
	}
}