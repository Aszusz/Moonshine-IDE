package com.palantir.ls.groovy;

import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.Stack;
import java.util.stream.Collectors;

import com.palantir.ls.util.Ranges;

import org.codehaus.groovy.ast.ASTNode;
import org.codehaus.groovy.ast.ClassCodeVisitorSupport;
import org.codehaus.groovy.ast.ClassNode;
import org.codehaus.groovy.ast.ConstructorNode;
import org.codehaus.groovy.ast.FieldNode;
import org.codehaus.groovy.ast.MethodNode;
import org.codehaus.groovy.ast.Parameter;
import org.codehaus.groovy.ast.PropertyNode;
import org.codehaus.groovy.ast.expr.ArgumentListExpression;
import org.codehaus.groovy.ast.expr.ArrayExpression;
import org.codehaus.groovy.ast.expr.AttributeExpression;
import org.codehaus.groovy.ast.expr.BinaryExpression;
import org.codehaus.groovy.ast.expr.BitwiseNegationExpression;
import org.codehaus.groovy.ast.expr.BooleanExpression;
import org.codehaus.groovy.ast.expr.CastExpression;
import org.codehaus.groovy.ast.expr.ClassExpression;
import org.codehaus.groovy.ast.expr.ClosureExpression;
import org.codehaus.groovy.ast.expr.ClosureListExpression;
import org.codehaus.groovy.ast.expr.ConstantExpression;
import org.codehaus.groovy.ast.expr.ConstructorCallExpression;
import org.codehaus.groovy.ast.expr.DeclarationExpression;
import org.codehaus.groovy.ast.expr.ElvisOperatorExpression;
import org.codehaus.groovy.ast.expr.FieldExpression;
import org.codehaus.groovy.ast.expr.GStringExpression;
import org.codehaus.groovy.ast.expr.ListExpression;
import org.codehaus.groovy.ast.expr.MapEntryExpression;
import org.codehaus.groovy.ast.expr.MapExpression;
import org.codehaus.groovy.ast.expr.MethodCallExpression;
import org.codehaus.groovy.ast.expr.MethodPointerExpression;
import org.codehaus.groovy.ast.expr.NotExpression;
import org.codehaus.groovy.ast.expr.PostfixExpression;
import org.codehaus.groovy.ast.expr.PrefixExpression;
import org.codehaus.groovy.ast.expr.PropertyExpression;
import org.codehaus.groovy.ast.expr.RangeExpression;
import org.codehaus.groovy.ast.expr.SpreadExpression;
import org.codehaus.groovy.ast.expr.SpreadMapExpression;
import org.codehaus.groovy.ast.expr.StaticMethodCallExpression;
import org.codehaus.groovy.ast.expr.TernaryExpression;
import org.codehaus.groovy.ast.expr.TupleExpression;
import org.codehaus.groovy.ast.expr.UnaryMinusExpression;
import org.codehaus.groovy.ast.expr.UnaryPlusExpression;
import org.codehaus.groovy.ast.expr.VariableExpression;
import org.codehaus.groovy.ast.stmt.AssertStatement;
import org.codehaus.groovy.ast.stmt.BlockStatement;
import org.codehaus.groovy.ast.stmt.BreakStatement;
import org.codehaus.groovy.ast.stmt.CaseStatement;
import org.codehaus.groovy.ast.stmt.CatchStatement;
import org.codehaus.groovy.ast.stmt.ContinueStatement;
import org.codehaus.groovy.ast.stmt.DoWhileStatement;
import org.codehaus.groovy.ast.stmt.EmptyStatement;
import org.codehaus.groovy.ast.stmt.ExpressionStatement;
import org.codehaus.groovy.ast.stmt.ForStatement;
import org.codehaus.groovy.ast.stmt.IfStatement;
import org.codehaus.groovy.ast.stmt.ReturnStatement;
import org.codehaus.groovy.ast.stmt.SwitchStatement;
import org.codehaus.groovy.ast.stmt.SynchronizedStatement;
import org.codehaus.groovy.ast.stmt.ThrowStatement;
import org.codehaus.groovy.ast.stmt.TryCatchStatement;
import org.codehaus.groovy.ast.stmt.WhileStatement;
import org.codehaus.groovy.classgen.BytecodeExpression;
import org.codehaus.groovy.control.SourceUnit;
import org.eclipse.lsp4j.Position;
import org.eclipse.lsp4j.Range;

public class ASTNodeVisitor extends ClassCodeVisitorSupport
{
	private SourceUnit sourceUnit;

	public SourceUnit getSourceUnit()
	{
		return sourceUnit;
	}

	public void setSourceUnit(SourceUnit sourceUnit)
	{
		this.sourceUnit = sourceUnit;
	}

	private Stack<ASTNode> stack = new Stack<>();
	private Set<ASTNode> nodes = new HashSet<>();
	private Map<ASTNode, ASTNode> parents = new HashMap<>();

	private void pushASTNode(ASTNode node) {
		nodes.add(node);
		if(stack.size() > 0)
		{
			ASTNode parent = stack.lastElement();
			parents.put(node, parent);
		}
		stack.add(node);
	}

	private void popASTNode() {
		stack.pop();
	}

	public ASTNode getNodeAtLineAndColumn(int line, int column)
	{
		final Position position = new Position(line, column);
		final Map<ASTNode, Range> nodeToRange = new HashMap<>();
		List<ASTNode> foundNodes = nodes.stream()
			.filter(node -> {
				Range range = Ranges.createZeroBasedRange(node.getLineNumber(), node.getColumnNumber(), node.getLastLineNumber(), node.getLastColumnNumber());
				if(!Ranges.isValid(range)) {
					return false;
				}
				boolean result = Ranges.contains(range, position);
				if(result)
				{
					//save the range object to avoid creating it again when we
					//sort the nodes
					nodeToRange.put(node, range);
				}
				return result;
			})
			// If there is more than one result, we want the symbol whose range starts the latest, with a secondary
			// sort of earliest end range.
			.sorted((n1, n2) -> Ranges.POSITION_COMPARATOR.compare(
				nodeToRange.get(n1).getEnd(),
				nodeToRange.get(n2).getEnd()
			))
			.sorted((n1, n2) -> Ranges.POSITION_COMPARATOR.reversed().compare(
				nodeToRange.get(n1).getStart(),
				nodeToRange.get(n2).getStart()
			))
			.collect(Collectors.toList());
		if(foundNodes.size() == 0)
		{
			return null;
		}
		return foundNodes.get(0);
	}

	public ASTNode getParent(ASTNode child) {
		//get() returns null if there's no parent
		return parents.get(child);
	}

	// GroovyClassVisitor

    public void visitClass(ClassNode node)
	{
		pushASTNode(node);
		try
		{
			super.visitClass(node);
		}
		finally
		{
			popASTNode();
		}
	}

    public void visitConstructor(ConstructorNode node)
	{
		pushASTNode(node);
		try
		{
			super.visitConstructor(node);
		}
		finally
		{
			popASTNode();
		}
	}

    public void visitMethod(MethodNode node)
	{
		pushASTNode(node);
		try
		{
			super.visitMethod(node);
			for(Parameter parameter : node.getParameters())
			{
				visitParameter(parameter);
			}
		}
		finally
		{
			popASTNode();
		}
	}

	protected void visitParameter(Parameter node)
	{
		pushASTNode(node);
		try
		{
		}
		finally
		{
			popASTNode();
		}
	}

    public void visitField(FieldNode node)
	{
		pushASTNode(node);
		try
		{
			super.visitField(node);
		}
		finally
		{
			popASTNode();
		}
	}

	public void visitProperty(PropertyNode node)
	{
		pushASTNode(node);
		try
		{
			super.visitProperty(node);
		}
		finally
		{
			popASTNode();
		}
	}

	// GroovyCodeVisitor

    public void visitBlockStatement(BlockStatement node) {
		pushASTNode(node);
		try
		{
			super.visitBlockStatement(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitForLoop(ForStatement node) {
		pushASTNode(node);
		try
		{
			super.visitForLoop(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitWhileLoop(WhileStatement node) {
		pushASTNode(node);
		try
		{
			super.visitWhileLoop(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitDoWhileLoop(DoWhileStatement node) {
		pushASTNode(node);
		try
		{
			super.visitDoWhileLoop(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitIfElse(IfStatement node) {
		pushASTNode(node);
		try
		{
			super.visitIfElse(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitExpressionStatement(ExpressionStatement node) {
		pushASTNode(node);
		try
		{
			super.visitExpressionStatement(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitReturnStatement(ReturnStatement node) {
		pushASTNode(node);
		try
		{
			super.visitReturnStatement(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitAssertStatement(AssertStatement node) {
		pushASTNode(node);
		try
		{
			super.visitAssertStatement(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitTryCatchFinally(TryCatchStatement node) {
		pushASTNode(node);
		try
		{
			super.visitTryCatchFinally(node);
		}
		finally
		{
			popASTNode();
		}
    }

    protected void visitEmptyStatement(EmptyStatement node) {
		pushASTNode(node);
		try
		{
			super.visitEmptyStatement(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitSwitch(SwitchStatement node) {
		pushASTNode(node);
		try
		{
			super.visitSwitch(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitCaseStatement(CaseStatement node) {
		pushASTNode(node);
		try
		{
			super.visitCaseStatement(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitBreakStatement(BreakStatement node) {
		pushASTNode(node);
		try
		{
			super.visitBreakStatement(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitContinueStatement(ContinueStatement node) {
		pushASTNode(node);
		try
		{
			super.visitContinueStatement(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitSynchronizedStatement(SynchronizedStatement node) {
		pushASTNode(node);
		try
		{
			super.visitSynchronizedStatement(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitThrowStatement(ThrowStatement node) {
		pushASTNode(node);
		try
		{
			super.visitThrowStatement(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitMethodCallExpression(MethodCallExpression node) {
		pushASTNode(node);
		try
		{
			super.visitMethodCallExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitStaticMethodCallExpression(StaticMethodCallExpression node) {
		pushASTNode(node);
		try
		{
			super.visitStaticMethodCallExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitConstructorCallExpression(ConstructorCallExpression node) {
		pushASTNode(node);
		try
		{
			super.visitConstructorCallExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitBinaryExpression(BinaryExpression node) {
		pushASTNode(node);
		try
		{
			super.visitBinaryExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitTernaryExpression(TernaryExpression node) {
		pushASTNode(node);
		try
		{
			super.visitTernaryExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitShortTernaryExpression(ElvisOperatorExpression node) {
		pushASTNode(node);
		try
		{
			super.visitShortTernaryExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitPostfixExpression(PostfixExpression node) {
		pushASTNode(node);
		try
		{
			super.visitPostfixExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitPrefixExpression(PrefixExpression node) {
		pushASTNode(node);
		try
		{
			super.visitPrefixExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitBooleanExpression(BooleanExpression node) {
		pushASTNode(node);
		try
		{
			super.visitBooleanExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitNotExpression(NotExpression node) {
		pushASTNode(node);
		try
		{
			super.visitNotExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitClosureExpression(ClosureExpression node) {
		pushASTNode(node);
		try
		{
			super.visitClosureExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitTupleExpression(TupleExpression node) {
		pushASTNode(node);
		try
		{
			super.visitTupleExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitListExpression(ListExpression node) {
		pushASTNode(node);
		try
		{
			super.visitListExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitArrayExpression(ArrayExpression node) {
		pushASTNode(node);
		try
		{
			super.visitArrayExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitMapExpression(MapExpression node) {
		pushASTNode(node);
		try
		{
			super.visitMapExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitMapEntryExpression(MapEntryExpression node) {
		pushASTNode(node);
		try
		{
			super.visitMapEntryExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitRangeExpression(RangeExpression node) {
		pushASTNode(node);
		try
		{
			super.visitRangeExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitSpreadExpression(SpreadExpression node) {
		pushASTNode(node);
		try
		{
			super.visitSpreadExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitSpreadMapExpression(SpreadMapExpression node) {
		pushASTNode(node);
		try
		{
			super.visitSpreadMapExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitMethodPointerExpression(MethodPointerExpression node) {
		pushASTNode(node);
		try
		{
			super.visitMethodPointerExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitUnaryMinusExpression(UnaryMinusExpression node) {
		pushASTNode(node);
		try
		{
			super.visitUnaryMinusExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitUnaryPlusExpression(UnaryPlusExpression node) {
		pushASTNode(node);
		try
		{
			super.visitUnaryPlusExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitBitwiseNegationExpression(BitwiseNegationExpression node) {
		pushASTNode(node);
		try
		{
			super.visitBitwiseNegationExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitCastExpression(CastExpression node) {
		pushASTNode(node);
		try
		{
			super.visitCastExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitConstantExpression(ConstantExpression node) {
		pushASTNode(node);
		try
		{
			super.visitConstantExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitClassExpression(ClassExpression node) {
		pushASTNode(node);
		try
		{
			super.visitClassExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitVariableExpression(VariableExpression node) {
		pushASTNode(node);
		try
		{
			super.visitVariableExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitDeclarationExpression(DeclarationExpression node) {
		pushASTNode(node);
		try
		{
			super.visitDeclarationExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitPropertyExpression(PropertyExpression node) {
		pushASTNode(node);
		try
		{
			super.visitPropertyExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitAttributeExpression(AttributeExpression node) {
		pushASTNode(node);
		try
		{
			super.visitAttributeExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitFieldExpression(FieldExpression node) {
		pushASTNode(node);
		try
		{
			super.visitFieldExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitGStringExpression(GStringExpression node) {
		pushASTNode(node);
		try
		{
			super.visitGStringExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitCatchStatement(CatchStatement node) {
		pushASTNode(node);
		try
		{
			super.visitCatchStatement(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitArgumentlistExpression(ArgumentListExpression node) {
		pushASTNode(node);
		try
		{
			super.visitArgumentlistExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitClosureListExpression(ClosureListExpression node) {
		pushASTNode(node);
		try
		{
			super.visitClosureListExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }

    public void visitBytecodeExpression(BytecodeExpression node) {
		pushASTNode(node);
		try
		{
			super.visitBytecodeExpression(node);
		}
		finally
		{
			popASTNode();
		}
    }
}