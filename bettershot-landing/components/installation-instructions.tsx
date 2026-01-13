"use client"

import { useState } from "react"
import { Download, Terminal, AlertCircle, Copy, Check } from "lucide-react"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"

const COMMAND = "xattr -d com.apple.quarantine /Applications/bettershot.app"

export function InstallationInstructions() {
  const [copied, setCopied] = useState(false)

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(COMMAND)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch (err) {
      console.error("Failed to copy:", err)
    }
  }

  return (
    <section className="w-full py-16 px-4 sm:px-6 lg:px-8 relative z-10">
      <div className="container mx-auto max-w-4xl">
        <div className="text-center mb-12">
          <h2 className="text-3xl sm:text-4xl font-bold mb-4 text-foreground">Installation</h2>
          <p className="text-muted-foreground text-lg">
            Download the .dmg file for your Mac
          </p>
        </div>

        <div className="grid gap-6">
          <Card>
            <CardHeader>
              <div className="flex items-center gap-3 mb-2">
                <Download className="h-5 w-5 text-primary" />
                <CardTitle>Step 1: Download</CardTitle>
              </div>
              <CardDescription>
                Choose the version that matches your Mac
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="space-y-3">
                <div>
                  <p className="text-sm font-medium mb-1">Apple Silicon (M1, M2, M3)</p>
                  <p className="text-sm text-muted-foreground">
                    Download the aarch64 version
                  </p>
                </div>
                <div>
                  <p className="text-sm font-medium mb-1">Intel Mac</p>
                  <p className="text-sm text-muted-foreground">
                    Download the x64 version
                  </p>
                </div>
              </div>
              <p className="text-sm text-muted-foreground mt-4">
                Open the DMG and drag Better Shot to Applications
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <div className="flex items-center gap-3 mb-2">
                <Terminal className="h-5 w-5 text-primary" />
                <CardTitle>Step 2: First Launch</CardTitle>
              </div>
              <CardDescription>
                Terminal Method (One command, no dialogs) - Recommended
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="bg-[#1a1a1a] rounded-lg p-4 border border-border mb-4 relative group">
                <code className="text-sm text-[#e5e5e5] font-mono block pr-12 select-all">
                  {COMMAND}
                </code>
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={handleCopy}
                  className="absolute top-2 right-2 h-8 w-8 p-0 hover:bg-background/50"
                  aria-label="Copy command"
                >
                  {copied ? (
                    <Check className="h-4 w-4 text-green-500" />
                  ) : (
                    <Copy className="h-4 w-4" />
                  )}
                </Button>
              </div>
              <p className="text-sm text-muted-foreground mb-4">
                Grant Screen Recording permission when prompted in System Settings
              </p>
              <div className="flex items-start gap-3 p-4 rounded-lg bg-amber-500/10 border border-amber-500/20">
                <AlertCircle className="h-5 w-5 text-amber-500 mt-0.5 shrink-0" />
                <div className="flex-1">
                  <p className="text-sm font-medium text-amber-500 mb-1">
                    Note about app signing
                  </p>
                  <p className="text-sm text-muted-foreground">
                    This is an ad-hoc signed indie app. macOS shows a warning for apps not notarized through Apple's $99/year developer program. The app is completely safe and open source.
                  </p>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </section>
  )
}
