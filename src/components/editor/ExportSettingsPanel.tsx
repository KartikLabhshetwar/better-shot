import { memo } from "react";
import { FolderOpen, ImageDown, Loader2 } from "lucide-react";

interface ExportSettingsPanelProps {
  saveDir: string;
  exportName: string;
  isSaving: boolean;
  imageLoaded: boolean;
  onSaveDirChange: (value: string) => void;
  onExportNameChange: (value: string) => void;
  onBrowseSaveDir: () => void;
  onSave: () => void;
}

export const ExportSettingsPanel = memo(function ExportSettingsPanel({
  saveDir,
  exportName,
  isSaving,
  imageLoaded,
  onSaveDirChange,
  onExportNameChange,
  onBrowseSaveDir,
  onSave,
}: ExportSettingsPanelProps) {
  return (
    <div>
      {/* Save directory */}
      <div className="section-header" style={{ paddingTop: 0 }}>
        <span className="section-title">Save Location</span>
      </div>
      <div style={{ display: 'flex', gap: 6, alignItems: 'center', marginBottom: 16 }}>
        <input
          id="save-dir-input"
          type="text"
          value={saveDir}
          onChange={(e) => onSaveDirChange(e.target.value)}
          placeholder="~/Desktop"
          className="studio-input"
          style={{ flex: 1, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}
        />
        <button
          onClick={onBrowseSaveDir}
          aria-label="Browse for save directory"
          style={{
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            width: 30, height: 30, flexShrink: 0,
            background: 'oklch(0.20 0.008 250)',
            border: '1px solid oklch(0.26 0.009 250)',
            borderRadius: 6,
            color: 'oklch(0.55 0.012 250)',
            cursor: 'pointer',
            transition: 'all 0.12s ease',
          }}
          onMouseEnter={(e) => {
            (e.currentTarget as HTMLButtonElement).style.borderColor = 'oklch(0.45 0.012 250)';
            (e.currentTarget as HTMLButtonElement).style.color = 'oklch(0.75 0.01 250)';
          }}
          onMouseLeave={(e) => {
            (e.currentTarget as HTMLButtonElement).style.borderColor = 'oklch(0.26 0.009 250)';
            (e.currentTarget as HTMLButtonElement).style.color = 'oklch(0.55 0.012 250)';
          }}
        >
          <FolderOpen className="size-[14px]" />
        </button>
      </div>

      {/* Export name */}
      <div className="section-header">
        <span className="section-title">Filename</span>
      </div>
      <input
        id="export-name"
        type="text"
        value={exportName}
        onChange={(e) => onExportNameChange(e.target.value)}
        placeholder="bettershot_123456789.png"
        className="studio-input"
      />
      <div style={{ marginTop: 6, marginBottom: 20, fontSize: 10, color: 'oklch(0.38 0.009 250)' }}>
        Leave blank to use auto-generated name
      </div>

      {/* Export button */}
      <button
        onClick={onSave}
        disabled={!imageLoaded || isSaving}
        className="header-btn header-btn-primary"
        style={{ width: '100%', justifyContent: 'center', padding: '9px 14px', fontSize: 13 }}
        aria-label="Export image"
      >
        {isSaving
          ? <Loader2 className="size-[14px] animate-spin" />
          : <ImageDown className="size-[14px]" />
        }
        <span>{isSaving ? 'Exporting…' : 'Export'}</span>
      </button>
    </div>
  );
});
