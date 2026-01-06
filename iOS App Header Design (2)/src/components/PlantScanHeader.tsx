export function PlantScanHeader() {
  return (
    <header className="relative w-full h-[140px] overflow-hidden">
      {/* Fresh Green Gradient Background */}
      <div className="absolute inset-0 bg-gradient-to-br from-emerald-500 via-green-500 to-teal-600" />
      
      {/* Repeating White Leaf Pattern - Low Opacity */}
      <div className="absolute inset-0 opacity-[0.08]">
        <svg className="w-full h-full" xmlns="http://www.w3.org/2000/svg">
          <defs>
            <pattern id="leaf-pattern" x="0" y="0" width="100" height="100" patternUnits="userSpaceOnUse">
              {/* Simple repeating leaf shapes */}
              <path 
                d="M20 30 Q25 20 30 30 Q25 40 20 30 Z" 
                fill="white"
              />
              <path 
                d="M70 65 Q75 55 80 65 Q75 75 70 65 Z" 
                fill="white"
              />
              <path 
                d="M45 80 Q48 73 51 80 Q48 87 45 80 Z" 
                fill="white"
              />
              <path 
                d="M15 75 L18 78 L15 81 L12 78 Z" 
                fill="white"
              />
              <path 
                d="M85 20 L88 23 L85 26 L82 23 Z" 
                fill="white"
              />
              <circle cx="55" cy="25" r="3" fill="white" />
              <circle cx="30" cy="60" r="2" fill="white" />
              <path 
                d="M60 50 Q62 48 64 50" 
                stroke="white" 
                strokeWidth="1.5" 
                fill="none"
              />
            </pattern>
          </defs>
          <rect width="100%" height="100%" fill="url(#leaf-pattern)" />
        </svg>
      </div>
      
      {/* Large Left Leaf Silhouette - Decorative */}
      <div className="absolute -left-16 top-1/2 -translate-y-1/2 w-40 h-48 opacity-20">
        <svg viewBox="0 0 160 192" fill="none" xmlns="http://www.w3.org/2000/svg">
          {/* Main leaf body */}
          <path
            d="M15 96 Q15 35 65 10 Q78 25 72 96 Q65 150 50 165 Q25 165 15 125 Q12 110 15 96 Z"
            fill="white"
          />
          {/* Secondary leaflets */}
          <path
            d="M72 96 Q77 45 105 25 Q118 40 112 96 Q108 125 98 140"
            fill="white"
            opacity="0.6"
          />
          <path
            d="M72 96 Q85 55 120 40 Q133 55 127 100 Q125 120 118 135"
            fill="white"
            opacity="0.35"
          />
          {/* Leaf veins */}
          <path
            d="M35 55 Q50 52 65 55"
            stroke="white"
            strokeWidth="2"
            opacity="0.25"
            fill="none"
          />
          <path
            d="M32 75 Q50 72 68 75"
            stroke="white"
            strokeWidth="2"
            opacity="0.25"
            fill="none"
          />
          <path
            d="M30 95 Q50 92 70 95"
            stroke="white"
            strokeWidth="2"
            opacity="0.25"
            fill="none"
          />
          <path
            d="M28 115 Q48 112 68 115"
            stroke="white"
            strokeWidth="2"
            opacity="0.25"
            fill="none"
          />
        </svg>
      </div>
      
      {/* Large Right Leaf Silhouette - Decorative (Mirrored) */}
      <div className="absolute -right-16 top-1/2 -translate-y-1/2 w-40 h-48 opacity-20 scale-x-[-1]">
        <svg viewBox="0 0 160 192" fill="none" xmlns="http://www.w3.org/2000/svg">
          {/* Main leaf body */}
          <path
            d="M15 96 Q15 35 65 10 Q78 25 72 96 Q65 150 50 165 Q25 165 15 125 Q12 110 15 96 Z"
            fill="white"
          />
          {/* Secondary leaflets */}
          <path
            d="M72 96 Q77 45 105 25 Q118 40 112 96 Q108 125 98 140"
            fill="white"
            opacity="0.6"
          />
          <path
            d="M72 96 Q85 55 120 40 Q133 55 127 100 Q125 120 118 135"
            fill="white"
            opacity="0.35"
          />
          {/* Leaf veins */}
          <path
            d="M35 55 Q50 52 65 55"
            stroke="white"
            strokeWidth="2"
            opacity="0.25"
            fill="none"
          />
          <path
            d="M32 75 Q50 72 68 75"
            stroke="white"
            strokeWidth="2"
            opacity="0.25"
            fill="none"
          />
          <path
            d="M30 95 Q50 92 70 95"
            stroke="white"
            strokeWidth="2"
            opacity="0.25"
            fill="none"
          />
          <path
            d="M28 115 Q48 112 68 115"
            stroke="white"
            strokeWidth="2"
            opacity="0.25"
            fill="none"
          />
        </svg>
      </div>
      
      {/* Clean Title Area with Strong Contrast */}
      <div className="absolute inset-0 flex items-center justify-center">
        {/* Subtle backdrop for enhanced contrast */}
        <div className="absolute bg-black/5 backdrop-blur-[2px] rounded-2xl px-12 py-4" />
        
        {/* Title Text */}
        <h1 
          className="relative text-white text-[22pt] font-bold tracking-tight drop-shadow-[0_2px_8px_rgba(0,0,0,0.15)]" 
          style={{ fontFamily: '"Gotham", "Gotham SSm", "Montserrat", -apple-system, BlinkMacSystemFont, "SF Pro Display", system-ui, sans-serif' }}
        >
          Plant Scan
        </h1>
      </div>
    </header>
  );
}