export const dynamic = "force-static"

export async function GET() {
  const llmsContent = `# Better Shot

> An open-source alternative to CleanShot X for macOS. Capture, edit, and enhance your screenshots with professional quality.

Better Shot is a free, open-source screenshot tool designed for macOS users who want a powerful yet accessible solution for capturing, annotating, and sharing screenshots. Built with modern web technologies and packaged as a native macOS application, Better Shot provides professional-grade features without the premium price tag.

The application offers comprehensive screenshot capabilities including region selection, full-screen capture, window capture, and timed captures. Users can enhance their screenshots with built-in editing tools, annotations, background effects, and various styling options.

## Core Resources

[Homepage]: https://bettershot.site - Main landing page with product information, features, and download links

[GitHub Repository]: https://github.com/KartikLabhshetwar/better-shot - Source code, documentation, and issue tracking

[Documentation]: https://github.com/KartikLabhshetwar/better-shot - Technical documentation and development guides

## Key Features

- **Screenshot Capture**: Region, full-screen, window, and timed capture modes
- **Image Editing**: Built-in annotation tools, effects, and styling options
- **Background Effects**: Multiple background options and customization
- **Open Source**: Free and open-source under permissive license
- **Native macOS**: Optimized for macOS with native performance

## Technical Details

Better Shot is built using:
- React and TypeScript for the user interface
- Tauri for native macOS application packaging
- Modern web technologies for cross-platform compatibility

The project welcomes contributions from the open-source community and is actively maintained.
`

  return new Response(llmsContent, {
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
    },
  })
}
