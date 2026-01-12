# Contributing to Better Shot

Thank you for your interest in contributing to Better Shot! This document provides guidelines and instructions for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [Coding Standards](#coding-standards)
- [Testing](#testing)
- [Pull Request Process](#pull-request-process)
- [Technology Stack](#technology-stack)

## Code of Conduct

Be respectful, constructive, and professional in all interactions. Focus on the code and ideas, not the person.

## Getting Started

1. **Fork the repository** and clone your fork:

   ```bash
   git clone https://github.com/YOUR_USERNAME/better-shot.git
   cd better-shot
   ```

2. **Install dependencies:**

   ```bash
   pnpm install
   ```

3. **Set up development environment:**
   - Ensure you have Rust installed (for Tauri backend)
   - Ensure you have Node.js 18+ and pnpm installed
   - On macOS, grant Screen Recording permission when prompted

## Development Setup

### Prerequisites

- **Node.js**: 18 or higher
- **pnpm**: Latest version
- **Rust**: Latest stable version (for Tauri)
- **macOS**: Required for development (app is macOS-specific)

### Running the Application

Start the development server:

```bash
pnpm tauri dev
```

This will:
- Start the Vite dev server for the frontend
- Compile the Rust backend
- Launch the Tauri application window with hot-reload

### Building for Production

```bash
pnpm tauri build
```

The installer will be located in `src-tauri/target/release/bundle/`

### Linting

Run TypeScript type checking:

```bash
pnpm lint:ci
```

### Testing

Run Rust tests:

```bash
pnpm test:rust
```

## Project Structure

```text
bettershot/
├── src/                    # Frontend React application
│   ├── components/         # React components
│   │   ├── editor/         # Image editor components
│   │   │   ├── AnnotationCanvas.tsx    # Canvas for drawing annotations
│   │   │   ├── AnnotationToolbar.tsx   # Toolbar for annotation tools
│   │   │   ├── PropertiesPanel.tsx     # Panel for editing annotation properties
│   │   │   ├── BackgroundSelector.tsx  # Background selection UI
│   │   │   ├── AssetGrid.tsx           # Asset library grid
│   │   │   ├── EffectsPanel.tsx        # Blur and noise controls
│   │   │   └── ImageRoundnessControl.tsx # Border radius control
│   │   ├── landing/        # Landing page components
│   │   └── ui/             # Reusable UI primitives
│   ├── lib/                # Utility functions
│   │   ├── annotation-utils.ts  # Annotation rendering utilities
│   │   ├── canvas-utils.ts      # Canvas manipulation utilities
│   │   └── utils.ts              # General utilities
│   ├── types/              # TypeScript type definitions
│   │   └── annotations.ts  # Annotation type definitions
│   └── assets/             # Static assets (images, etc.)
├── src-tauri/              # Rust backend (Tauri)
│   ├── src/
│   │   ├── commands.rs     # Tauri command handlers
│   │   ├── clipboard.rs    # Clipboard operations
│   │   ├── image.rs        # Image processing
│   │   ├── screenshot.rs   # Screenshot capture
│   │   ├── utils.rs        # Utility functions
│   │   └── lib.rs          # Application entry point
│   └── Cargo.toml          # Rust dependencies
├── AGENTS.md               # UI/UX design guidelines
└── package.json            # Node.js dependencies and scripts
```

## Coding Standards

### General Principles

1. **Search First**: Before implementing, search the codebase for similar functionality
2. **Reuse First**: Extend existing patterns and components before creating new ones
3. **No Assumptions**: Only use information from files, user messages, or tool results
4. **SOLID Principles**: Keep code simple but maintain separation of concerns
5. **File Size**: Aim to keep files under 300 lines - split when it improves clarity

### TypeScript/React Guidelines

- **No Code Comments**: Write self-explanatory code instead
- **Alphabetical Imports**: Keep imports sorted alphabetically
- **Strict TypeScript**: All code must pass `pnpm lint:ci` (TypeScript strict mode)
- **Type Safety**: Use proper TypeScript types, avoid `any`
- **Component Structure**:
  - Use functional components with hooks
  - Keep components focused and single-purpose
  - Extract reusable logic into custom hooks

### Rust Guidelines

- **Error Handling**: Use `Result<T, String>` for error handling
- **Documentation**: Use `//!` for module-level docs, `///` for function docs
- **Module Organization**: Keep modules focused and well-organized
- **Async/Await**: Use async/await for Tauri commands
- **Resource Management**: Properly handle file paths and temporary files

### UI/UX Guidelines

Refer to `AGENTS.md` for detailed UI/UX constraints. Key points:

#### Stack

- **MUST** use Tailwind CSS defaults (spacing, radius, shadows) before custom values
- **MUST** use `motion/react` (formerly `framer-motion`) when JavaScript animation is required
- **MUST** use `cn` utility (`clsx` + `tailwind-merge`) for class logic

#### Components

- **MUST** use accessible component primitives for keyboard/focus behavior (`Base UI`, `React Aria`, `Radix`)
- **MUST** use the project's existing component primitives first
- **MUST** add `aria-label` to icon-only buttons
- **NEVER** rebuild keyboard or focus behavior by hand

#### Interaction

- **MUST** use `AlertDialog` for destructive or irreversible actions
- **SHOULD** use structural skeletons for loading states
- **NEVER** use `h-screen`, use `h-dvh`
- **MUST** respect `safe-area-inset` for fixed elements
- **MUST** show errors next to where the action happens

#### Animation

- **NEVER** add animation unless explicitly requested
- **MUST** animate only compositor props (`transform`, `opacity`)
- **NEVER** animate layout properties (`width`, `height`, `top`, `left`, `margin`, `padding`)
- **NEVER** exceed `200ms` for interaction feedback
- **MUST** respect `prefers-reduced-motion`

#### Typography

- **MUST** use `text-balance` for headings and `text-pretty` for body/paragraphs
- **MUST** use `tabular-nums` for data
- **SHOULD** use `truncate` or `line-clamp` for dense UI

#### Design

- **NEVER** use gradients unless explicitly requested
- **NEVER** use purple or multicolor gradients
- **NEVER** use glow effects as primary affordances
- **SHOULD** use Tailwind CSS default shadow scale
- **MUST** give empty states one clear next action

### Code Style

#### TypeScript/React

```typescript
// Good: Self-explanatory code, alphabetical imports
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { useState } from "react";

export function MyComponent() {
  const [value, setValue] = useState("");
  
  return (
    <Card>
      <CardContent>
        <Button onClick={() => setValue("test")}>Click</Button>
      </CardContent>
    </Card>
  );
}
```

#### Rust

```rust
// Good: Clear function names, proper error handling
pub async fn my_command(param: String) -> Result<String, String> {
    let result = process_data(&param)?;
    Ok(result)
}
```

## Testing

### When to Write Tests

Write tests for **critical paths only**:

- Core screenshot capture functionality
- Image processing operations
- Clipboard operations
- Annotation rendering and manipulation
- Error handling in critical flows

### Test Structure

Use AAA pattern (Arrange, Act, Assert) with comments:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_filename() {
        // Arrange
        let prefix = "screenshot";
        let extension = "png";

        // Act
        let filename = generate_filename(prefix, extension).unwrap();

        // Assert
        assert!(filename.starts_with(prefix));
        assert!(filename.ends_with(extension));
    }
}
```

### Running Tests

```bash
pnpm test:rust
```

## Pull Request Process

### Before Submitting

1. **Search the codebase** for similar functionality
2. **Reuse existing patterns** and components
3. **Run linting**: `pnpm lint:ci`
4. **Run tests**: `pnpm test:rust`
5. **Test manually**: Ensure the feature works in development mode

### PR Guidelines

1. **Clear Title**: Use descriptive, concise titles
2. **Description**: Explain what and why, not how (code shows how)
3. **Small PRs**: Prefer smaller, focused PRs over large ones
4. **One Feature**: One feature or fix per PR
5. **Branch Naming**: Use descriptive branch names (e.g., `fix/clipboard-error`, `feat/custom-shortcuts`)

### PR Template

When creating a PR, include:

- **What**: Brief description of changes
- **Why**: Reason for the change
- **Testing**: How you tested the changes
- **Screenshots**: If applicable (UI changes)

### Review Process

- All PRs require review before merging
- Address review comments promptly
- Keep discussions focused on code and ideas
- Be open to feedback and suggestions

## Technology Stack

### Frontend
- **React 19**: UI framework
- **TypeScript 5.8**: Type safety
- **Vite 7**: Build tool and dev server
- **Tailwind CSS 4**: Styling
- **Sonner**: Toast notifications

### Backend
- **Rust**: System programming language
- **Tauri 2**: Desktop app framework
- **xcap**: Screenshot capture library
- **arboard**: Clipboard operations
- **image**: Image processing

### Development Tools
- **pnpm**: Package manager
- **TypeScript**: Type checking
- **Cargo**: Rust package manager

## Common Tasks

### Adding a New Feature

1. Search for similar functionality
2. Check existing components/utilities
3. Create feature branch: `git checkout -b feat/feature-name`
4. Implement following coding standards
5. Test thoroughly
6. Run linting and tests
7. Submit PR

### Fixing a Bug

1. Reproduce the bug
2. Search codebase for related code
3. Create fix branch: `git checkout -b fix/bug-description`
4. Implement fix
5. Add test if it's a critical path
6. Run linting and tests
7. Submit PR with clear description

### Adding a New UI Component

1. Check `src/components/ui/` for existing primitives
2. Use existing primitives when possible
3. Follow UI guidelines from `AGENTS.md`
4. Ensure accessibility (keyboard navigation, ARIA labels)
5. Use `cn` utility for class merging
6. Test with different screen sizes

### Adding a New Annotation Type

1. Add the annotation type to `src/types/annotations.ts`
2. Update `AnnotationCanvas.tsx` to handle creation and rendering
3. Add tool icon to `AnnotationToolbar.tsx`
4. Add property controls to `PropertiesPanel.tsx` if needed
5. Update `annotation-utils.ts` for rendering logic
6. Test drawing, selection, movement, and deletion

## Getting Help

- **Issues**: Check existing issues before creating new ones
- **Discussions**: Use GitHub Discussions for questions
- **Code Review**: Be specific in review comments

## License

By contributing, you agree that your contributions will be licensed under the same license as the project.

---

Thank you for contributing to Better Shot! 🎉
