Welcome to the official **NeoStation** assets repository. Here you can find and contribute new visual styles to customize system art.

## Repository Structure

The structure is designed to be modular and easy to navigate for both humans and the application:
* `themes/`: Contains all individual system art folders.
* `preview/`: Global screenshots for the catalog display.
* `manifest.json`: Main index used by the app to list available system arts.

---

## How to Create a System Art

### 1. Folder Setup
Create a new folder inside `themes/` with a descriptive name (e.g., `Matrix-Green`).

### 2. The `theme.json` File
Each system art must include a `theme.json` file with metadata:
```json
{
  "id": "my-unique-art",
  "name": "Visual Name",
  "author": "Your Name",
  "version": "1.0.0",
  "description": "Short description of the style.",
  "ai": false
}
```

### 3. Asset Requirements

To ensure optimal performance on handheld and Android devices, please follow these technical specifications:

#### **Backgrounds**
* **Format:** Must be **.webp** (optimized) or **.gif** (animated).
* **Resolution:** Minimum **1024 x 1024** px.
* **Location:** `themes/[your-art]/backgrounds/`
* **Naming:** `[shortname].[extension]` (e.g., `gba.webp`, `ps1.gif`).
* **Fallback:** Always include a `default.webp` for unspecified systems.

## Publishing
Once your system art is ready, ensure you:
1. Add a screenshot to the `preview/` folder.
2. Register your system art in the `manifest.json` file at the root.
3. Open a Pull Request.

## Legal Information and Licensing

NeoStation Assets is a collection of original creative work and third-party trademarks.

- Original Assets: All custom backgrounds and original UI elements are licensed under CC BY-NC-SA 4.0.
- Trademarks: All console logos and brand names are the property of their respective owners. Their use here is for identification and educational purposes only.

For the full legal text, please refer to the LICENSE file in this repository.

## Contributions

We welcome contributions of new backgrounds or missing console logos. Please ensure any submitted work follows the quality standards of the project and respects the non-commercial nature of this repository.
